import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class YouPageModelTests: XCTestCase {
  func testTitleIsYou() {
    let model = YouPageModel()
    expectNoDifference(model.title, "You")
  }
}
