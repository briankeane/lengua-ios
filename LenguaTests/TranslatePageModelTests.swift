import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class TranslatePageModelTests: XCTestCase {
  func testEnglishLabel() {
    expectNoDifference(TranslatePageModel().englishLabel, "English")
  }

  func testEnglishPlaceholder() {
    expectNoDifference(TranslatePageModel().englishPlaceholder, "Type or speak English")
  }

  func testSpeakItHint() {
    expectNoDifference(TranslatePageModel().speakItHint, "Speak it")
  }

  func testSpanishLabel() {
    expectNoDifference(TranslatePageModel().spanishLabel, "Spanish")
  }

  func testSpanishPlaceholder() {
    expectNoDifference(TranslatePageModel().spanishPlaceholder, "Spanish")
  }
}
