import AVFoundation
import Dependencies
import Foundation

extension SpeechSynthesizerClient: DependencyKey {
  static var liveValue: SpeechSynthesizerClient {
    let engine = SpeechSynthesisEngine()
    return SpeechSynthesizerClient(
      speak: { text, languageIdentifier in
        try await engine.speak(text, languageIdentifier: languageIdentifier)
      },
      stop: { await engine.stop() }
    )
  }
}

/// Owns a single `AVSpeechSynthesizer` and bridges its delegate callbacks into
/// async/await. One utterance at a time: a new `speak` stops the previous one.
private final class SpeechSynthesisEngine: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var continuation: CheckedContinuation<Void, Error>?
  /// The utterance the current `continuation` is waiting on. Delegate callbacks
  /// carry the utterance they fired for; a callback only resolves the
  /// continuation when its utterance is still the current one. Without this,
  /// tapping speak again mid-playback (which stops the first utterance) lets the
  /// first utterance's later `didCancel` prematurely resolve the *second*
  /// operation.
  private var currentUtterance: AVSpeechUtterance?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  @MainActor
  func speak(_ text: String, languageIdentifier: String) async throws {
    stopImmediately()
    try configureAudioSession()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: languageIdentifier)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      self.continuation = continuation
      self.currentUtterance = utterance
      synthesizer.speak(utterance)
    }
  }

  @MainActor
  func stop() {
    stopImmediately()
  }

  private func stopImmediately() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    resume(with: .success(()))
  }

  private func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try session.setActive(true)
  }

  private func resume(with result: Result<Void, Error>) {
    currentUtterance = nil
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }

  /// Resolves the pending continuation only if `utterance` is the one it is
  /// waiting on — a stale callback from a superseded utterance is ignored.
  private func resumeIfCurrent(_ utterance: AVSpeechUtterance) {
    guard utterance === currentUtterance else { return }
    resume(with: .success(()))
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in resumeIfCurrent(utterance) }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in resumeIfCurrent(utterance) }
  }
}

// State is confined to the main actor via the @MainActor methods; the delegate
// callbacks only hop back onto it. Conformance is declared here (not inline) so
// the multi-line class declaration stays lint-clean.
extension SpeechSynthesisEngine: @unchecked Sendable {}
