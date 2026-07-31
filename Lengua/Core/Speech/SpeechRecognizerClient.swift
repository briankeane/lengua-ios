import Dependencies
import DependenciesMacros
import Foundation

/// A single (partial or final) speech-recognition result.
struct SpeechRecognitionResult: Sendable, Equatable {
  var transcript: String
  var isFinal: Bool
}

/// App-domain authorization status. Kept separate from Apple's
/// `SFSpeechRecognizerAuthorizationStatus` so the framework type never reaches
/// the page model.
enum SpeechAuthorizationStatus: Sendable, Equatable {
  case notDetermined
  case denied
  case restricted
  case authorized
}

/// Streams live speech-to-text. `start` returns a stream of partial transcripts
/// that finishes when the caller `stop`s or the recognizer completes. The live
/// engine (SFSpeechRecognizer + AVAudioEngine) is an implementation detail.
@DependencyClient
struct SpeechRecognizerClient: Sendable {
  var authorizationStatus: @Sendable () async -> SpeechAuthorizationStatus = { .notDetermined }
  var requestAuthorization: @Sendable () async -> SpeechAuthorizationStatus = { .denied }
  var start:
    @Sendable (_ localeIdentifier: String) async throws
      -> AsyncThrowingStream<SpeechRecognitionResult, Error>
  var stop: @Sendable () async -> Void
}

extension DependencyValues {
  var speechRecognizer: SpeechRecognizerClient {
    get { self[SpeechRecognizerClient.self] }
    set { self[SpeechRecognizerClient.self] = newValue }
  }
}

extension SpeechRecognizerClient: TestDependencyKey {
  static let testValue = SpeechRecognizerClient()
}
