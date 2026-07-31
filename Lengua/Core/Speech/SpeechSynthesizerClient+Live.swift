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
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in resume(with: .success(())) }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in resume(with: .success(())) }
  }
}

// State is confined to the main actor via the @MainActor methods; the delegate
// callbacks only hop back onto it. Conformance is declared here (not inline) so
// the multi-line class declaration stays lint-clean.
extension SpeechSynthesisEngine: @unchecked Sendable {}
