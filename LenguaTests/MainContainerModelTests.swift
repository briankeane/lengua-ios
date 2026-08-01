import CustomDump
import Testing

@testable import Lengua

@MainActor
struct MainContainerModelTests {
  @Test func activeTabHasFiveExpectedCases() {
    expectNoDifference(
      MainContainerModel.ActiveTab.allCases,
      [.lookUp, .library, .review, .talk, .you])
  }

  @Test func tabTitles() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabTitle, "Look up")
    expectNoDifference(model.libraryTabTitle, "Library")
    expectNoDifference(model.reviewTabTitle, "Review")
    expectNoDifference(model.talkTabTitle, "Talk")
    expectNoDifference(model.youTabTitle, "You")
  }

  @Test func tabIconNames() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabIconName, "magnifyingglass")
    expectNoDifference(model.libraryTabIconName, "books.vertical")
    expectNoDifference(model.reviewTabIconName, "checkmark.square")
    expectNoDifference(model.talkTabIconName, "waveform")
    expectNoDifference(model.youTabIconName, "person")
  }
}
