# Translate page wiring + translation provider selection — design

**Date:** 2026-07-31
**Branch:** `briankeane/connect-translator-to-page`
**Status:** Approved design (pending spec review)

## Goal

Two user-requested features:

1. **Make the Translate page work end to end.** Editable English/Spanish input,
   debounced auto-translate through the existing `TranslatorClient`, translated
   output, a mic button (on-device speech-to-text into the input), a speaker
   button (on-device text-to-speech of the output), and a swap button that flips
   the translation **direction** (English↔Spanish, bidirectional). Speech input
   locale and speech output voice follow the current direction.
2. **Add a translation-provider setting to the You (profile) page.** Choose Apple
   vs DeepL. DeepL is shown but **disabled** (not ready). The choice persists
   across launches and actually drives which provider `TranslatorClient` uses.

## Current state (what already exists)

- The translation **service** is built: `TranslatorClient` (`@Dependency(\.translator)`)
  with `translate(englishText)` and `availability()`, backed by
  `AppleTranslationProvider` (Apple on-device `Translation` framework) and a
  `DeepLTranslationProvider` stub, selected by `TranslationProviderSelector.current`
  (hardcoded `.apple`). `TranslatorClient+Live` hardcodes source `en` → target `es`.
- `AppleTranslationBroker` bridges Apple's SwiftUI-only `TranslationSession` into
  the non-UI client; a host is mounted once via `.translatorHost()` in `ContentView`.
  **It assumes a single active language pair** (caches one `configuration`, only
  rebuilds when `nil`).
- `TranslatePage` is a **pure UI stub**: no text input field; static placeholder
  text; empty `micButtonTapped` / `swapButtonTapped` / `speakerButtonTapped`.
- `YouPage` has name/email + a Sign Out button; **no settings rows**.
- `SharedUserDefaults.swift` has `.auth` (file), and `.activeTab` /
  `.mainContainerNavigationCoordinator` / `.appVersionRequirements` (in-memory).
  **No `appStorage`-backed key exists yet.**

## Conventions (must follow)

- MV pattern with `@Observable` models. Model holds all logic + display strings;
  View is visuals only.
- External effects go through `@DependencyClient` structs, injected via
  `@Dependency`, mocked in tests via `withDependencies`.
- Cross-launch prefs via swift-sharing `@Shared` + a `SharedKey`.
- swift-testing only, tests colocated. `expectNoDifference`/`expectDifference`
  from CustomDump. `@MainActor` throughout. No `Task.sleep` in tests.
- Invoke the relevant `pfw-*` skills before writing each piece of code.

## Architecture decisions (from Codex consult, session 019fb7b1)

### A. `TranslationDirection` enum (not loose `Locale.Language` params)

The domain is exactly English↔Spanish. Model that directly:

```swift
enum TranslationDirection: String, Sendable, Equatable, CaseIterable, Codable {
  case englishToSpanish
  case spanishToEnglish

  var source: Locale.Language { … }
  var target: Locale.Language { … }
  var inputLabel: String { … }   // "English" / "Spanish"
  var outputLabel: String { … }  // "Spanish" / "English"
  var speechRecognitionLocaleIdentifier: String { … }   // "en-US" / "es-ES"
  var speechSynthesisLanguageIdentifier: String { … }   // "en-US" / "es-ES"
  mutating func toggle() { … }
}
```

`TranslatorClient` becomes direction-aware; the provider protocol keeps its
low-level `from:/to:` seam:

```swift
@DependencyClient
struct TranslatorClient: Sendable {
  var translate: @Sendable (_ text: String, _ direction: TranslationDirection) async throws -> String
  var availability: @Sendable (_ direction: TranslationDirection) async -> TranslatorAvailability = { _ in .unknown }
}
```

The `en→es` hardcoding moves out of `+Live` into the direction's `source`/`target`.
The blank-input-short-circuits-to-`""` contract is preserved.

### B. Broker: session identity includes the language pair

Bug: `AppleTranslationBroker` treats a non-`nil` `configuration` as "correct
session," which is false once the pair changes — an `es→en` request could drain
through a stale `en→es` session (wrong output / opaque failure).

Minimal fix:

- Introduce `struct TranslationPair: Sendable, Equatable { source; target }`.
- Store the active pair on the broker and on each `PendingRequest`.
- `requestSessionIfNeeded(pair:)` rebuilds the `TranslationSession.Configuration`
  when `activePair != pair`.
- `drainQueue(using:)` only drains requests matching the session's pair; when the
  next queued request is a different pair, stop and request a fresh configuration
  for that pair. Never drain mixed pairs through one session.

Queue / cancellation / fail-fast-when-no-host logic is otherwise unchanged.

### C. Speech-to-text and text-to-speech as separate dependency clients

```swift
@DependencyClient
struct SpeechRecognizerClient: Sendable {
  var authorizationStatus: @Sendable () async -> SpeechAuthorizationStatus = { .notDetermined }
  var requestAuthorization: @Sendable () async -> SpeechAuthorizationStatus = { .denied }
  var start: @Sendable (_ localeIdentifier: String) async throws -> AsyncThrowingStream<SpeechRecognitionResult, Error>
  var stop: @Sendable () async -> Void
}

struct SpeechRecognitionResult: Sendable, Equatable { var transcript: String; var isFinal: Bool }
enum SpeechAuthorizationStatus: Sendable, Equatable { case notDetermined, denied, authorized, restricted }

@DependencyClient
struct SpeechSynthesizerClient: Sendable {
  var speak: @Sendable (_ text: String, _ languageIdentifier: String) async throws -> Void
  var stop: @Sendable () async -> Void
}
```

- Live `SpeechRecognizerClient` wraps `SFSpeechRecognizer` +
  `SFSpeechAudioBufferRecognitionRequest` + `SFSpeechRecognitionTask` +
  `AVAudioEngine` in a `@MainActor` holder. On-device recognition where available.
- Live `SpeechSynthesizerClient` wraps `AVSpeechSynthesizer`.
- Domain permission enum only — never leak `SFSpeechRecognizerAuthorizationStatus`
  into the model. Permission-denied → a `LenguaAlert`.
- Add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` in the
  STT stage.

### D. Debounced auto-translate via `\.continuousClock`

```swift
@Dependency(\.translator) var translator
@Dependency(\.continuousClock) var clock

var inputText = "" { didSet { scheduleTranslation() } }
var outputText = ""
var direction: TranslationDirection = .englishToSpanish
@ObservationIgnored private var translationTask: Task<Void, Never>?

private func scheduleTranslation() {
  translationTask?.cancel()
  let text = inputText, direction = direction
  translationTask = Task { @MainActor in
    do {
      try await clock.sleep(for: .milliseconds(500))
      try Task.checkCancellation()
      let translated = try await translator.translate(text, direction)
      try Task.checkCancellation()
      guard inputText == text, self.direction == direction else { return }
      outputText = translated
    } catch is CancellationError {
    } catch { outputText = ""; presentedAlert = .translationFailed }
  }
}
```

Swap cancels the in-flight task, swaps the two texts, and reschedules. Tests use a
test clock: advance 499ms → no call; +1ms → call fires. No `Task.sleep`.

### E. Provider preference — wired dynamically now (no split-brain)

- `TranslationProviderKind` becomes `String`-backed + `Codable`, with
  `var isEnabled: Bool` (`.apple` = true, `.deepL` = false) and a display name.
- New shared key:

  ```swift
  extension SharedKey where Self == AppStorageKey<TranslationProviderKind>.Default {
    static var translationProviderKind: Self {
      Self[.appStorage("translationProviderKind"), default: .apple]
    }
  }
  ```

- `TranslationProviderSelector.current` reads `@Shared(.translationProviderKind)`
  instead of returning a constant.
- `TranslatorHost` observes the same shared value so the Apple host mounts/unmounts
  correctly if the provider changes.
- `YouPageModel` holds `@Shared(.translationProviderKind)`, exposes a provider list
  with per-item enabled state + selection, and a `selectProvider(_:)` action that
  ignores disabled providers. `YouPage` renders a provider row; DeepL visible but
  disabled.

## Implementation stages (staged commits on this branch)

1. **Bidirectional translator core** — `TranslationDirection`; direction-aware
   `TranslatorClient` + `+Live`; broker pair-correctness fix (`TranslationPair`,
   rebuild-on-pair-change, no mixed-pair drains). Update existing translator tests.
   Deliverable: service translates both directions correctly; no UI change yet.
2. **Provider preference** — `TranslationProviderKind` `String`/`Codable`+`isEnabled`;
   `.appStorage` shared key; selector + `TranslatorHost` read it; You page provider
   row (DeepL disabled). Deliverable: feature #2 complete, persists across launches.
3. **Translate page core** — editable input field; `outputText`; `direction` state;
   debounced auto-translate via `\.continuousClock`; swap flips direction + swaps
   text; loading + error states; all display strings direction-derived. Deliverable:
   type → translate → read, both directions.
4. **Text-to-speech** — `SpeechSynthesizerClient` + live `AVSpeechSynthesizer`;
   speaker button speaks `outputText` in the target language. Deliverable: hear the
   translation.
5. **Speech-to-text** — `SpeechRecognizerClient` + live impl; mic button starts/stops
   dictation into `inputText` in the source language; permission handling + alerts;
   Info.plist usage strings. Deliverable: speak the input.

Each stage: TDD where possible, compiles, `make test` + `make lint` green,
committed with a message linking to this spec. Codex adversarial review on the
non-trivial stages (1, 3, 5) before moving on.

## Testing

- Direction enum: label/locale/toggle mapping (`TranslationDirectionTests`).
- `TranslatorClient`: direction passthrough via injected mock; blank-input `""`;
  error propagation (extend existing `TranslatorClientTests`).
- Broker pair correctness: a pair change forces a new configuration; requests for a
  different pair are not drained through the wrong session (`AppleTranslationBroker`
  logic is testable at the queue level without a live session).
- `TranslatePageModel`: debounce timing with a test clock; staleness guard; swap
  behavior; error → alert; mic/speaker actions call injected speech clients.
- `YouPageModel`: provider list, selecting enabled vs disabled provider, persisted
  value drives selection.
- Convert `TranslatePageModelTests.swift` from XCTest to swift-testing (it is touched
  in stage 3).

## Non-goals

- Language pairs other than English↔Spanish.
- Real DeepL implementation (stub stays; setting is disabled).
- Server-side translation (there is no translate endpoint; all on-device).
