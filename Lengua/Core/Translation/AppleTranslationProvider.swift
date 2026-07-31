import Foundation
import SwiftUI
import Translation

/// A concrete source→target language pair. Session identity in the broker
/// includes the pair, so a direction flip forces a fresh session instead of
/// reusing one configured for the previous pair.
struct TranslationPair: Sendable, Equatable {
  var source: Locale.Language
  var target: Locale.Language

  /// True when both pairs describe the same translation direction, comparing
  /// only `languageCode` (not script or region).
  ///
  /// Apple canonicalizes a `TranslationSession`'s resolved languages (e.g.
  /// `"en"` → `"en-Latn-US"`), so a pair derived from a live session may not be
  /// `==` a request pair built from minimal identifiers (`"en"` / `"es"`).
  /// Full `Locale.Language` equality would then match nothing, hanging every
  /// translation. Comparing language codes is canonicalization-proof and
  /// sufficient for the app's en/es scope.
  ///
  /// Fail-closed on a missing code: if any `languageCode` is `nil` this returns
  /// `false` rather than letting two unspecified languages coalesce (which a
  /// plain `nil == nil` would). Unreachable for en/es, but this keeps a
  /// malformed pair from ever draining through the wrong session.
  func matches(_ other: TranslationPair) -> Bool {
    guard
      let selfSource = source.languageCode, let otherSource = other.source.languageCode,
      let selfTarget = target.languageCode, let otherTarget = other.target.languageCode
    else { return false }
    return selfSource == otherSource && selfTarget == otherTarget
  }
}

/// Live provider backed by Apple's on-device Translation framework (iOS 18+).
///
/// IMPORTANT: Apple's `TranslationSession` is SwiftUI-only — it can only be
/// vended inside a view via `.translationTask`, and it does **not** run in the
/// iOS Simulator (real device only). This provider therefore holds no session
/// itself; it forwards to `AppleTranslationBroker`, a `@MainActor` holder that a
/// small root-mounted SwiftUI host (`AppleTranslationHost`) feeds with live
/// sessions. `LanguageAvailability` is view-independent, so `availability` works
/// without a mounted host.
struct AppleTranslationProvider: TranslationProvider {
  func translate(
    _ text: String, from source: Locale.Language, to target: Locale.Language
  ) async throws -> String {
    // Surface an unsupported pair up front rather than letting it collapse into
    // an opaque `.translationFailed` from the session. (`.downloadRequired` is
    // intentionally not thrown here — a download is user-mediated and is
    // surfaced via `availability()`; a translate proceeds and lets the session
    // prompt the download.)
    if await availability(from: source, to: target) == .unsupported {
      throw TranslatorError.unsupportedLanguagePair
    }
    return try await AppleTranslationBroker.shared.translate(text, from: source, to: target)
  }

  func availability(
    from source: Locale.Language, to target: Locale.Language
  ) async -> TranslatorAvailability {
    let status = await LanguageAvailability().status(from: source, to: target)
    switch status {
    case .installed: return .installed
    case .supported: return .downloadRequired
    case .unsupported: return .unsupported
    @unknown default: return .unknown
    }
  }
}

/// Bridges the SwiftUI-vended `TranslationSession` into the non-UI Translator
/// service. `translate` enqueues a request and asks the host for a session; when
/// the host hands back a live session, `drainQueue` translates every queued
/// request through it.
///
/// The `TranslationSession` never leaves this main actor and is never stored,
/// which sidesteps the "retained session invalidated when the task re-runs"
/// pitfall — each drain uses only the session handed to it for that run.
///
/// Session identity includes the active language pair (`TranslationPair`), so
/// a direction flip forces a fresh session rather than draining through one
/// configured for the previous pair.
@MainActor
@Observable
final class AppleTranslationBroker {
  static let shared = AppleTranslationBroker()

  /// Drives the host's `.translationTask`. Setting it (or calling
  /// `invalidate()`) causes the host to request a fresh session.
  var configuration: TranslationSession.Configuration?

  /// The language pair the current `configuration` was built for. Session
  /// identity = this pair; a request for a different pair forces a rebuild.
  @ObservationIgnored private var activePair: TranslationPair?

  /// Unresolved requests keyed by id. Presence == not yet resumed; `finish`
  /// removes the entry, so every continuation is resumed exactly once even when
  /// a drain and a cancellation race for the same request.
  @ObservationIgnored private var requests: [UUID: PendingRequest] = [:]
  /// Ids awaiting a session, in FIFO order.
  @ObservationIgnored private var queue: [UUID] = []
  @ObservationIgnored private var isDraining = false
  /// Number of mounted hosts able to vend a session. When zero, no session can
  /// ever arrive, so a request must fail fast instead of suspending forever.
  @ObservationIgnored private var mountedHostCount = 0

  private struct PendingRequest {
    let id: UUID
    let text: String
    let pair: TranslationPair
    let continuation: CheckedContinuation<String, Error>
  }

  /// Called by a host when it appears. Only while at least one host is mounted
  /// can `translate` obtain a session.
  func hostDidMount() { mountedHostCount += 1 }

  /// Called by a host when it disappears. If the last host goes away, no session
  /// can arrive, so any still-waiting requests fail with `.notReady` rather than
  /// hanging.
  func hostDidUnmount() {
    mountedHostCount = max(0, mountedHostCount - 1)
    if mountedHostCount == 0 {
      failAll(with: TranslatorError.notReady)
    }
  }

  func translate(
    _ text: String, from source: Locale.Language, to target: Locale.Language
  ) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    // No mounted host means no session can ever be vended (e.g. the host was
    // never mounted, or we are in a context — like the Simulator — where the
    // Translation UI is absent). Fail fast rather than suspending indefinitely.
    guard mountedHostCount > 0 else { throw TranslatorError.notReady }

    let pair = TranslationPair(source: source, target: target)
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        requests[id] = PendingRequest(id: id, text: text, pair: pair, continuation: continuation)
        queue.append(id)
        requestSessionIfNeeded(for: pair)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) }
    }
  }

  /// Called by the host with a live session. Prepares the on-device model, then
  /// translates every queued request for the pair this session was configured
  /// for — including ones enqueued while an earlier `session.translate` is
  /// awaiting — through this one session. Requests for a different pair (e.g.
  /// enqueued after a direction flip) are left queued and re-armed afterward.
  func drainQueue(using session: TranslationSession) async {
    // Only one drain runs at a time. A redundant session (e.g. a second mounted
    // host) is dropped; the active drain already picks up newly-enqueued work.
    guard !isDraining else { return }
    isDraining = true
    // The pair this session actually serves, derived below from the session
    // itself. Captured for the defer so `rearmIfNeeded` can tell whether any
    // leftover request is for a *different* pair (re-arm) or the same pair we
    // just drained (do not re-arm — that would spin the host's task).
    var drainedPair: TranslationPair?
    defer {
      isDraining = false
      rearmIfNeeded(afterDraining: drainedPair)
    }

    // Derive the pair from the session itself rather than the broker's
    // `activePair`. `activePair` is mutable request state: Apple vends a
    // session asynchronously, so a rapid second direction flip can advance
    // `activePair` to a different pair before this session (built for the
    // *previous* pair) is actually delivered here. Reading the pair off the
    // session Apple handed us is authoritative and closes that race.
    guard let source = session.sourceLanguage, let target = session.targetLanguage else {
      // The broker always configures sessions with an explicit source/target,
      // so this should be unreachable; fail safe rather than misroute.
      return
    }
    let pair = TranslationPair(source: source, target: target)
    drainedPair = pair

    do {
      // Ensures the language model is downloaded/ready, prompting the user if
      // needed. Failure here means the model is unavailable — surface it as
      // `.downloadRequired` rather than an opaque translate failure.
      try await session.prepareTranslation()
    } catch {
      // Only fail requests for THIS pair; other-pair requests are re-armed.
      failAll(matching: pair, with: TranslatorError.downloadRequired)
      return
    }

    // Drain every queued request for this pair, including ones enqueued while an
    // earlier `session.translate` was awaiting. Leave other-pair requests queued.
    // Match on `pair.matches(_:)` (language code), NOT `==`: Apple canonicalizes
    // the session's languages (e.g. "en" → "en-Latn-US"), so full
    // `Locale.Language` equality against a request pair built from "en"/"es"
    // would match nothing and hang every translation.
    // Known tradeoff: this scans past other-pair requests rather than stopping
    // at the first one, so sustained same-pair traffic could in principle delay
    // a queued opposite-pair request indefinitely. Acceptable here — the
    // Translate page only ever has one in-flight request at a time, not a
    // continuous stream — but worth revisiting if usage changes.
    while let id = queue.first(where: { id in
      guard let request = requests[id] else { return false }
      return pair.matches(request.pair)
    }) {
      queue.removeAll { $0 == id }
      guard let request = requests[id] else { continue }  // already cancelled
      do {
        let response = try await session.translate(request.text)
        finish(id, .success(response.targetText))
      } catch {
        finish(id, .failure(TranslatorError.translationFailed(String(describing: error))))
      }
    }
  }

  private func requestSessionIfNeeded(for pair: TranslationPair) {
    // While a drain is in flight, never touch `configuration`. If the drain is
    // for this same pair, its loop already picks up newly-enqueued same-pair
    // requests — no new session needed. If it's for a different pair,
    // rebuilding `configuration` now would restart the host's
    // `.translationTask` and risk cancelling the still-running drain.
    // `rearmIfNeeded()` requests a fresh session for a leftover pair once the
    // active drain completes.
    guard !isDraining else { return }

    if activePair != pair {
      // New pair: force a fresh session configured for it. Setting a new
      // configuration re-runs the host's `.translationTask`.
      activePair = pair
      configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
    } else if configuration == nil {
      configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
    } else {
      // Same pair, session exists: re-run the task to get a fresh session for
      // the newly-enqueued request.
      configuration?.invalidate()
    }
  }

  /// After a drain, if requests for a *different* pair remain, request a fresh
  /// session for the next one so it drains too.
  ///
  /// Zero-match guard: if the front pending request is for the pair we just
  /// drained (`afterDraining`), do NOT re-arm. A fresh session would resolve to
  /// the same pair and drain the same (zero) requests, so re-arming would spin
  /// an unbounded `invalidate()`/`prepareTranslation` loop. This makes the
  /// broker robust even if the pair-match logic ever fails to match a request
  /// that should have been drained: at worst that request stays pending until a
  /// genuinely different request arrives, instead of pinning the CPU.
  private func rearmIfNeeded(afterDraining drainedPair: TranslationPair?) {
    guard let nextId = queue.first, let next = requests[nextId] else { return }
    if let drainedPair, drainedPair.matches(next.pair) { return }
    requestSessionIfNeeded(for: next.pair)
  }

  /// Resolves a single request exactly once. A no-op if it was already resolved
  /// (e.g. cancelled while in-flight, then the drain's translate returns).
  private func finish(_ id: UUID, _ result: Result<String, Error>) {
    guard let request = requests.removeValue(forKey: id) else { return }
    queue.removeAll { $0 == id }
    request.continuation.resume(with: result)
  }

  /// Fails pending requests. Pass a `pair` to fail only that pair's requests;
  /// pass `nil` to fail everything (e.g. when the last host unmounts).
  private func failAll(matching pair: TranslationPair? = nil, with error: Error) {
    let ids = requests.values
      .filter { request in
        // Match on language code (`matches`), not `==`, for the same
        // canonicalization reason as the drain loop: a session-derived `pair`
        // may not be `==` a request pair built from minimal identifiers.
        guard let pair else { return true }
        return pair.matches(request.pair)
      }
      .map(\.id)
    for id in ids {
      finish(id, .failure(error))
    }
  }
}

/// Invisible SwiftUI host that owns the Apple `.translationTask`. Mounted for us
/// by `TranslatorHost` when Apple is the active provider.
struct AppleTranslationHost: View {
  @State private var broker = AppleTranslationBroker.shared

  var body: some View {
    Color.clear
      .translationTask(broker.configuration) { session in
        await broker.drainQueue(using: session)
      }
      .onAppear { broker.hostDidMount() }
      .onDisappear { broker.hostDidUnmount() }
  }
}

/// Provider-neutral host for the Translator service. Mount ONE near the app root
/// via `.translatorHost()`. Only the Apple provider needs a SwiftUI-vended
/// session host; cloud providers (DeepL) need none, so this gates on the active
/// provider and app composition stays provider-agnostic.
struct TranslatorHost: View {
  var body: some View {
    if TranslationProviderSelector.current == .apple {
      AppleTranslationHost()
    }
  }
}

extension View {
  /// Mounts the Translator service's session host (if the active provider needs
  /// one). Apply once near the app root.
  func translatorHost() -> some View {
    background(TranslatorHost())
  }
}
