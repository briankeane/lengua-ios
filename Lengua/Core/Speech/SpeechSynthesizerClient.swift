import Dependencies
import DependenciesMacros
import Foundation

/// Speaks text aloud in a given language (text-to-speech). The page model uses
/// this for the speaker button; the underlying engine (AVSpeechSynthesizer) is
/// an implementation detail in `liveValue`.
@DependencyClient
struct SpeechSynthesizerClient: Sendable {
  /// Speaks `text` using a voice for `languageIdentifier` (e.g. "es-ES").
  /// Resolves when speech finishes (or is stopped).
  var speak: @Sendable (_ text: String, _ languageIdentifier: String) async throws -> Void
  /// Stops any in-progress speech immediately.
  var stop: @Sendable () async -> Void
}

extension DependencyValues {
  var speechSynthesizer: SpeechSynthesizerClient {
    get { self[SpeechSynthesizerClient.self] }
    set { self[SpeechSynthesizerClient.self] = newValue }
  }
}

extension SpeechSynthesizerClient: TestDependencyKey {
  static let testValue = SpeechSynthesizerClient()
}
