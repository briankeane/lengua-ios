import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Lengua

@MainActor
struct SpeechSynthesizerClientTests {
  @Test func speakUsesInjectedDependency() async throws {
    let spoken = LockIsolated<(String, String)?>(nil)
    try await withDependencies {
      $0.speechSynthesizer.speak = { text, language in
        spoken.setValue((text, language))
      }
    } operation: {
      @Dependency(\.speechSynthesizer) var synthesizer
      try await synthesizer.speak("Hola", "es-ES")
    }
    expectNoDifference(spoken.value?.0, "Hola")
    expectNoDifference(spoken.value?.1, "es-ES")
  }
}
