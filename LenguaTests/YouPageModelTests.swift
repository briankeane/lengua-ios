import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import XCTest

@testable import Lengua

@MainActor
final class YouPageModelTests: XCTestCase {
  func testTitleIsYou() {
    let model = YouPageModel()
    expectNoDifference(model.title, "You")
  }

  func testSignOutButtonTitle() {
    let model = YouPageModel()
    expectNoDifference(model.signOutButtonTitle, "Sign Out")
  }

  func testDisplayNameAndEmailReflectCurrentUser() {
    @Shared(.auth) var auth = Auth(
      jwtToken: "t",
      currentUser: User(
        id: "1", email: "a@b.com", firstName: "Sam", lastName: nil, profileImageUrl: nil))
    let model = YouPageModel()
    expectNoDifference(model.displayName, "Sam")
    expectNoDifference(model.emailText, "a@b.com")
  }

  func testDisplayNameFallsBackWhenNoName() {
    @Shared(.auth) var auth = Auth()
    let model = YouPageModel()
    expectNoDifference(model.displayName, "Signed in")
    XCTAssertNil(model.emailText)
  }

  func testSignOutButtonTappedCallsAuthClientSignOut() async {
    @Shared(.auth) var auth = Auth(jwtToken: "t")
    let signedOut = LockIsolated(false)
    let model = withDependencies {
      $0.authClient.signOut = { signedOut.setValue(true) }
    } operation: {
      YouPageModel()
    }

    await model.signOutButtonTapped()

    XCTAssertTrue(signedOut.value)
  }
}
