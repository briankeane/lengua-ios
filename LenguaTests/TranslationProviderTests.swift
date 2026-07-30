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

  @Test func brokerReturnsEmptyForBlankInputWithoutSession() async throws {
    let result = try await AppleTranslationBroker.shared.translate(
      "   \n ", from: english, to: spanish)
    #expect(result == "")
  }

  // No session host is mounted in tests, so a non-blank request stays queued
  // forever unless the caller cancels — which verifies the broker's
  // cancellation path unblocks a waiter instead of leaking it (and that the
  // "host never mounted" case does not hang uncancelled callers indefinitely).
  @Test func brokerCancellationUnblocksWaiter() async {
    let task = Task { @MainActor in
      try await AppleTranslationBroker.shared.translate("Hello", from: english, to: spanish)
    }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}
