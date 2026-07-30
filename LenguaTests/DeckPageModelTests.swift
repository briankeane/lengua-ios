import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class DeckPageModelTests: XCTestCase {
  func testTitleIsDeck() {
    let model = DeckPageModel()
    expectNoDifference(model.title, "Deck")
  }
}
