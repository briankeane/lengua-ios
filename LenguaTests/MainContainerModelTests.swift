import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class MainContainerModelTests: XCTestCase {
  func testActiveTabHasFiveExpectedCases() {
    expectNoDifference(
      MainContainerModel.ActiveTab.allCases,
      [.lookUp, .deck, .review, .talk, .you]
    )
  }

  func testTabTitles() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabTitle, "Look up")
    expectNoDifference(model.deckTabTitle, "Deck")
    expectNoDifference(model.reviewTabTitle, "Review")
    expectNoDifference(model.talkTabTitle, "Talk")
    expectNoDifference(model.youTabTitle, "You")
  }

  func testTabIconNames() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabIconName, "magnifyingglass")
    expectNoDifference(model.deckTabIconName, "rectangle.stack")
    expectNoDifference(model.reviewTabIconName, "checkmark.square")
    expectNoDifference(model.talkTabIconName, "waveform")
    expectNoDifference(model.youTabIconName, "person")
  }
}
