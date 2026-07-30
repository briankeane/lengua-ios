import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class ReviewPageModelTests: XCTestCase {
  func testTitleIsReview() {
    let model = ReviewPageModel()
    expectNoDifference(model.title, "Review")
  }
}
