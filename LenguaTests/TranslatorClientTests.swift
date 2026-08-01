import CustomDump
import Dependencies
import Foundation
import Testing

@testable import Lengua

@MainActor
struct TranslatorClientTests {
  @Test func translatePassesTextAndDirectionToDependency() async throws {
    let result = try await withDependencies {
      $0.translator.translate = { text, direction in
        expectNoDifference(text, "Hello")
        expectNoDifference(direction, .englishToSpanish)
        return "Hola"
      }
    } operation: {
      @Dependency(\.translator) var translator
      return try await translator.translate("Hello", .englishToSpanish)
    }
    expectNoDifference(result, "Hola")
  }

  @Test func availabilityPassesDirectionToDependency() async {
    let result = await withDependencies {
      $0.translator.availability = { direction in
        expectNoDifference(direction, .spanishToEnglish)
        return .downloadRequired
      }
    } operation: {
      @Dependency(\.translator) var translator
      return await translator.availability(.spanishToEnglish)
    }
    expectNoDifference(result, .downloadRequired)
  }

  @Test func liveClientReturnsEmptyForBlankInputWithoutHittingProvider() async throws {
    // Blank input short-circuits to "" before any provider is invoked (safe in
    // the Simulator, where the Apple provider cannot run).
    let result = try await TranslatorClient.liveValue.translate("   \n\t ", .englishToSpanish)
    expectNoDifference(result, "")
  }

  @Test func translatePropagatesProviderError() async {
    await #expect(throws: TranslatorError.notImplemented) {
      try await withDependencies {
        $0.translator.translate = { _, _ in throw TranslatorError.notImplemented }
      } operation: {
        @Dependency(\.translator) var translator
        return try await translator.translate("Hello", .englishToSpanish)
      }
    }
  }

  @Test func prepareTranslationPassesDirectionToDependency() async throws {
    try await withDependencies {
      $0.translator.prepareTranslation = { direction in
        expectNoDifference(direction, .spanishToEnglish)
      }
    } operation: {
      @Dependency(\.translator) var translator
      try await translator.prepareTranslation(.spanishToEnglish)
    }
  }

  @Test func prepareTranslationPropagatesProviderError() async {
    await #expect(throws: TranslatorError.downloadRequired) {
      try await withDependencies {
        $0.translator.prepareTranslation = { _ in throw TranslatorError.downloadRequired }
      } operation: {
        @Dependency(\.translator) var translator
        try await translator.prepareTranslation(.englishToSpanish)
      }
    }
  }
}
