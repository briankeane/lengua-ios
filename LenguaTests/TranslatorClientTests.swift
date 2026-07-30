import CustomDump
import Dependencies
import Foundation
import Testing

@testable import Lengua

@MainActor
struct TranslatorClientTests {
  @Test func translateUsesInjectedDependency() async throws {
    let result = try await withDependencies {
      $0.translator.translate = { englishText in
        expectNoDifference(englishText, "Hello")
        return "Hola"
      }
    } operation: {
      @Dependency(\.translator) var translator
      return try await translator.translate("Hello")
    }
    expectNoDifference(result, "Hola")
  }

  @Test func availabilityUsesInjectedDependency() async {
    let result = await withDependencies {
      $0.translator.availability = { .downloadRequired }
    } operation: {
      @Dependency(\.translator) var translator
      return await translator.availability()
    }
    expectNoDifference(result, .downloadRequired)
  }

  @Test func liveClientReturnsEmptyForBlankInputWithoutHittingProvider() async throws {
    // Exercises the real live client contract: blank input short-circuits to ""
    // before any provider is invoked, so it is safe to call in the Simulator.
    let result = try await TranslatorClient.liveValue.translate("   \n\t ")
    expectNoDifference(result, "")
  }

  @Test func translatePropagatesProviderError() async {
    await #expect(throws: TranslatorError.notImplemented) {
      try await withDependencies {
        $0.translator.translate = { _ in throw TranslatorError.notImplemented }
      } operation: {
        @Dependency(\.translator) var translator
        return try await translator.translate("Hello")
      }
    }
  }
}
