import Sharing
import XCTest

@testable import Lengua

@MainActor
final class HomePageTests: XCTestCase {
  func testNavigationTitleIsHome() {
    let model = HomePageModel()
    XCTAssertEqual(model.navigationTitle, "Home")
  }

  func testGreetingUsesFirstNameWhenLoggedIn() {
    @Shared(.auth) var auth = Auth(
      jwtToken: "token",
      currentUser: User(
        id: "1", email: "a@b.com", firstName: "Sam", lastName: nil, profileImageUrl: nil)
    )
    let model = HomePageModel()
    XCTAssertEqual(model.greeting, "Hola, Sam!")
  }

  func testGreetingFallsBackWhenNoName() {
    @Shared(.auth) var auth = Auth()
    let model = HomePageModel()
    XCTAssertEqual(model.greeting, "Hola!")
  }
}
