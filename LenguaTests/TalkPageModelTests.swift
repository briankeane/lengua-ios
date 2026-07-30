import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class TalkPageModelTests: XCTestCase {
  func testTitleIsTalk() {
    let model = TalkPageModel()
    expectNoDifference(model.title, "Talk")
  }
}
