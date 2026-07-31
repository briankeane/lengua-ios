import Foundation
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct TranslationProviderTests {
  private let english = Locale.Language(identifier: "en")
  private let spanish = Locale.Language(identifier: "es")

  @Test func defaultProviderIsApple() {
    #expect(TranslationProviderSelector.current == .apple)
  }

  @Test func selectorReturnsAppleProviderForApple() {
    #expect(TranslationProviderSelector.provider(for: .apple) is AppleTranslationProvider)
  }

  @Test func selectorReturnsDeepLProviderForDeepL() {
    #expect(TranslationProviderSelector.provider(for: .deepL) is DeepLTranslationProvider)
  }

  @Test func deepLTranslateThrowsNotImplemented() async {
    let provider = DeepLTranslationProvider()
    await #expect(throws: TranslatorError.notImplemented) {
      try await provider.translate("Hello", from: english, to: spanish)
    }
  }

  @Test func deepLAvailabilityIsUnknown() async {
    let provider = DeepLTranslationProvider()
    let availability = await provider.availability(from: english, to: spanish)
    #expect(availability == .unknown)
  }

  @Test func brokerReturnsEmptyForBlankInputWithoutHost() async throws {
    // Blank input short-circuits before any host/session is required.
    let broker = AppleTranslationBroker()
    let result = try await broker.translate("   \n ", from: english, to: spanish)
    #expect(result == "")
  }

  @Test func brokerThrowsNotReadyWhenNoHostMounted() async {
    // A non-blank request with no mounted host fails fast instead of suspending
    // forever (Greptile P1). Caller cancellation is only a backstop.
    let broker = AppleTranslationBroker()
    await #expect(throws: TranslatorError.notReady) {
      try await broker.translate("Hello", from: english, to: spanish)
    }
  }

  @Test func brokerFailsPendingWithNotReadyWhenLastHostUnmounts() async {
    // A request that is waiting on a session is released with `.notReady` when
    // the last host disappears, rather than hanging.
    let broker = AppleTranslationBroker()
    broker.hostDidMount()
    let task = Task { @MainActor in
      try await broker.translate("Hello", from: english, to: spanish)
    }
    await Task.yield()
    broker.hostDidUnmount()
    await #expect(throws: TranslatorError.notReady) {
      try await task.value
    }
  }

  @Test func brokerCancellationUnblocksWaiter() async {
    // With a host mounted the request suspends waiting for a session; cancelling
    // the caller unblocks it with CancellationError rather than leaking it.
    let broker = AppleTranslationBroker()
    broker.hostDidMount()
    let task = Task { @MainActor in
      try await broker.translate("Hello", from: english, to: spanish)
    }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test func brokerRebuildsConfigurationWhenPairChanges() async {
    // Enqueue en→es, then es→en; the second must produce a configuration for the
    // new pair rather than reusing the first. `TranslationSession.Configuration`
    // exposes readable `source`/`target` on this SDK (confirmed via the
    // Translation.swiftinterface), so we observe the configuration flips to the
    // new source/target directly. Requests are left suspended (no real session
    // in tests) and released when the host unmounts.
    let english = Locale.Language(identifier: "en")
    let spanish = Locale.Language(identifier: "es")
    let broker = AppleTranslationBroker()
    broker.hostDidMount()

    let first = Task { @MainActor in
      try await broker.translate("Hello", from: english, to: spanish)
    }
    await Task.yield()
    let firstConfig = broker.configuration
    #expect(firstConfig?.source == english)
    #expect(firstConfig?.target == spanish)

    let second = Task { @MainActor in
      try await broker.translate("Hola", from: spanish, to: english)
    }
    await Task.yield()
    #expect(broker.configuration?.source == spanish)
    #expect(broker.configuration?.target == english)

    broker.hostDidUnmount()  // releases both waiters with .notReady
    _ = await first.result
    _ = await second.result
  }
}
