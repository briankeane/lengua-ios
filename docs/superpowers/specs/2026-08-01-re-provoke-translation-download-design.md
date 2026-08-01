# Re-provoke the translation download sheet

**Date:** 2026-08-01
**Branch:** `briankeane/re-provoke-translation-sheet`

## Problem

The Translate page relies on Apple's on-device Translation framework. iOS presents
its **system** "download translation model" sheet as a side effect of
`session.prepareTranslation()`, which today only runs when the user translates real
text (`AppleTranslationBroker.drainQueue`).

If the user accidentally dismisses that sheet, `prepareTranslation()` throws, the
broker reports `TranslatorError.downloadRequired`, and `TranslatePageModel` treats it
like any other failure: it clears the output and shows a generic "Translation Failed"
alert (`TranslatePage.swift:150-155`). The user is left with a blank output card and
**no way to bring the download sheet back** — the app has no translation ability until
the model is downloaded, and nothing re-provokes the sheet.

## Goal

When the selected direction's on-device model is **not installed**:

1. **Auto:** provoke the system download sheet once when the user lands on the Translate
   page, if the model is missing.
2. **Manual:** show a persistent, non-blank affordance on the output card
   ("<Target> translation needs to be downloaded" + a **Download** button) whose button
   re-provokes the system sheet. This is the reliable fallback and must never leave the
   user stranded.

After a successful download, translation of the current input resumes automatically.

## Key constraint

To actually **pop** the system sheet you must call `session.prepareTranslation()`,
which needs a live `TranslationSession` vended by the `.translationTask` inside
`AppleTranslationHost`. `TranslatorClient.availability()` only **queries**
`LanguageAvailability` — it does not pop the sheet. On page-appear the input may be
empty, and the broker's `translate()` short-circuits empty text to `""` without
provoking. So a **text-less "provoke download" path** is required.

## Design

### Layer 1 — Translation seam: text-less provoke path

- `TranslatorClient`: add
  `var prepareTranslation: @Sendable (_ direction: TranslationDirection) async throws -> Void`
  alongside `translate` / `availability`.
- `TranslationProvider` protocol: add
  `func prepareTranslation(from: Locale.Language, to: Locale.Language) async throws`.
  The DeepL/cloud stub throws `.notImplemented` (matches the existing stub posture).
- `AppleTranslationProvider.prepareTranslation`: guard the unsupported pair up front
  (same as `translate`), then forward to `AppleTranslationBroker.shared`.
- `AppleTranslationBroker`: today `PendingRequest` is a struct that always carries text.
  Convert it to an enum with two cases:
  - `.translate(id, text, pair, CheckedContinuation<String, Error>)`
  - `.prepare(id, pair, CheckedContinuation<Void, Error>)`
  Add `prepareTranslation(from:to:)` that enqueues a `.prepare` request through the
  **same** queue + `requestSessionIfNeeded` machinery as `translate`.
  In `drainQueue`, after `session.prepareTranslation()` succeeds, a `.prepare` request
  for the drained pair resolves with `.success(())`; a `.translate` request keeps its
  existing `session.translate` path. On the existing `prepareTranslation()` failure
  branch, `failAll(matching: pair, with: .downloadRequired)` already fails both kinds.

All existing broker hardening is preserved unchanged:
- single-drain guard (`isDraining`)
- pair matching by language code (`TranslationPair.matches`), not `==`
- `rearmIfNeeded` zero-match spin guard
- host-unmount fail-fast (`hostDidUnmount` → `failAll(.notReady)`)
- resolve-exactly-once (`finish`)

Because a `.prepare` request resolves and leaves the queue empty, `rearmIfNeeded`'s
existing guards prevent any spin.

### Layer 2 — Model: `TranslatePageModel`

Download-required is **page state**, not an alert.

New state:
```swift
var downloadRequiredDirection: TranslationDirection?
var isPreparingDownload = false
@ObservationIgnored private var autoPromptedDownloadDirections: Set<TranslationDirection> = []
```

Behavior:
- `scheduleTranslation()` catch gains `catch TranslatorError.downloadRequired`: set
  `downloadRequiredDirection = currentDirection`, clear output, stop translating, and do
  **not** set `presentedAlert`. Genuine failures still fall through to
  `.translationFailed`.
- `pageAppeared()`: query `availability(direction)`.
  - `.installed` → `downloadRequiredDirection = nil`.
  - `.downloadRequired` → set `downloadRequiredDirection`; if the direction has not been
    auto-prompted yet this model lifetime, auto-provoke (the **auto-gate**).
  - `.unsupported` → clear affordance (leave to existing failure handling).
  - `.unknown` (Simulator) → do nothing (never auto-loop).
- `downloadButtonTapped()` → `provokeDownload(for: direction)`:
  - guarded by `isPreparingDownload` (the **manual gate**) so taps can't stack.
  - on success: clear `downloadRequiredDirection`; if input is non-empty, re-run
    `scheduleTranslation()`.
  - on `.downloadRequired` (user dismissed again): keep the affordance. **Never**
    auto-re-provoke here.
  - all mutations guard `self.direction == direction` to ignore stale results.
- `swapButtonTapped()`: clear `downloadRequiredDirection` so the new direction is
  re-evaluated on the next translate / appear.

View helpers (all text lives in the model):
```swift
var showsDownloadPrompt: Bool { downloadRequiredDirection == direction }
var downloadPromptText: String { "\(direction.outputLabel) translation needs to be downloaded" }
var downloadButtonTitle: String { "Download" }
```

### Layer 3 — View: `TranslatePage`

- Add `.task { await model.pageAppeared() }`.
- Output card: when `model.showsDownloadPrompt`, render `downloadPromptText` +
  a Download button (calls `downloadButtonTapped`) instead of the empty placeholder.
  Visuals only; all strings come from the model.

### Loop prevention

Two independent gates, and one rule:
- **Auto-gate:** `autoPromptedDownloadDirections` — auto-provoke at most once per
  direction per model lifetime. Never re-fires on its own.
- **Manual gate:** `isPreparingDownload` — a Download tap can't stack a second provoke.
- **Rule:** never auto-re-provoke inside a catch. After a dismissal the affordance
  simply remains; nothing happens until the user taps Download or swaps direction.

This defeats the dismiss → `.downloadRequired` → re-provoke infinite loop that a naive
retry-on-failure would create (iOS re-pops the sheet on every `prepareTranslation()`
while the model is missing).

## YAGNI / cuts

- No separate "download model" abstraction below the provider. The real operation is
  `prepareTranslation()`.
- No polling of system download state. Success is signaled by `prepareTranslation()`
  returning.

## Testing

swift-testing, colocated (`TranslatePageModelTests`, broker tests). `@MainActor`
suites; `.serialized` where they touch process-global state. Use CustomDump
`expectNoDifference` for value comparisons.

- `.downloadRequired` from `translate` sets the affordance and no generic alert.
- `pageAppeared` calls `availability`, then auto-provokes once for a missing model.
- A second `pageAppeared` while still missing does **not** auto-provoke again.
- Manual `downloadButtonTapped` can provoke repeatedly, but not concurrently
  (`isPreparingDownload`).
- Successful prepare schedules translation for current non-empty input.
- Successful prepare for a stale direction does not mutate current-direction output.
- Broker: a `.prepare` request resolves on `prepareTranslation()` success and fails with
  `.downloadRequired` on failure, without regressing the drain/rearm behavior.

## Device caveat

The Translation framework (and thus the sheet, and the re-pop-after-dismiss behavior)
only works on a **real device**, not the Simulator. The model/broker logic is unit-tested
independently; the end-to-end sheet behavior must be verified on a device.
