import CustomDump
import Dependencies
import Testing

@testable import Lengua

@MainActor
struct SpeechRecognizerClientTests {
  @Test func startStreamsResultsFromInjectedDependency() async throws {
    let recognizer = withDependencies {
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.start = { locale in
        expectNoDifference(locale, "en-US")
        return AsyncThrowingStream { continuation in
          continuation.yield(SpeechRecognitionResult(transcript: "Hello", isFinal: false))
          continuation.yield(SpeechRecognitionResult(transcript: "Hello there", isFinal: true))
          continuation.finish()
        }
      }
    } operation: {
      @Dependency(\.speechRecognizer) var recognizer
      return recognizer
    }

    let status = await recognizer.requestAuthorization()
    expectNoDifference(status, .authorized)

    var transcripts: [String] = []
    for try await result in try await recognizer.start("en-US") {
      transcripts.append(result.transcript)
    }
    expectNoDifference(transcripts, ["Hello", "Hello there"])
  }
}
