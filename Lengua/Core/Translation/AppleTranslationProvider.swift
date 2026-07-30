import Foundation
import SwiftUI
import Translation

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
/// Assumes a single active language pair at a time, which matches the fixed
/// English → Spanish scope (`TranslatorClient` only ever requests en → es).
@MainActor
@Observable
final class AppleTranslationBroker {
  static let shared = AppleTranslationBroker()

  /// Drives the host's `.translationTask`. Setting it (or calling
  /// `invalidate()`) causes the host to request a fresh session.
  var configuration: TranslationSession.Configuration?

  /// Unresolved requests keyed by id. Presence == not yet resumed; `finish`
  /// removes the entry, so every continuation is resumed exactly once even when
  /// a drain and a cancellation race for the same request.
  @ObservationIgnored private var requests: [UUID: PendingRequest] = [:]
  /// Ids awaiting a session, in FIFO order.
  @ObservationIgnored private var queue: [UUID] = []
  @ObservationIgnored private var isDraining = false

  private struct PendingRequest {
    let id: UUID
    let text: String
    let continuation: CheckedContinuation<String, Error>
  }

  func translate(
    _ text: String, from source: Locale.Language, to target: Locale.Language
  ) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        requests[id] = PendingRequest(id: id, text: text, continuation: continuation)
        queue.append(id)
        requestSessionIfNeeded(source: source, target: target)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) }
    }
  }

  /// Called by the host with a live session. Prepares the on-device model, then
  /// translates every queued request — including ones enqueued while an earlier
  /// `session.translate` is awaiting — through this one session.
  func drainQueue(using session: TranslationSession) async {
    // Only one drain runs at a time. A redundant session (e.g. a second mounted
    // host) is dropped; the active drain already picks up newly-enqueued work.
    guard !isDraining else { return }
    isDraining = true
    defer { isDraining = false }

    do {
      // Ensures the language model is downloaded/ready, prompting the user if
      // needed. Failure here means the model is unavailable — surface it as
      // `.downloadRequired` rather than an opaque translate failure.
      try await session.prepareTranslation()
    } catch {
      failAll(with: TranslatorError.downloadRequired)
      return
    }

    while let id = queue.first {
      queue.removeFirst()
      guard let request = requests[id] else { continue }  // already cancelled
      do {
        let response = try await session.translate(request.text)
        finish(id, .success(response.targetText))
      } catch {
        finish(id, .failure(TranslatorError.translationFailed(String(describing: error))))
      }
    }
  }

  private func requestSessionIfNeeded(source: Locale.Language, target: Locale.Language) {
    if configuration == nil {
      configuration = TranslationSession.Configuration(source: source, target: target)
    } else if !isDraining {
      // A session already exists but no drain is running: re-run the host's
      // translation task to obtain a fresh session for the new request. While a
      // drain IS running, the loop above already picks up newly-enqueued
      // requests, so invalidating would needlessly cancel the active session.
      configuration?.invalidate()
    }
  }

  /// Resolves a single request exactly once. A no-op if it was already resolved
  /// (e.g. cancelled while in-flight, then the drain's translate returns).
  private func finish(_ id: UUID, _ result: Result<String, Error>) {
    guard let request = requests.removeValue(forKey: id) else { return }
    queue.removeAll { $0 == id }
    request.continuation.resume(with: result)
  }

  private func failAll(with error: Error) {
    let all = requests
    requests.removeAll()
    queue.removeAll()
    for request in all.values {
      request.continuation.resume(throwing: error)
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
