import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import Testing

@testable import Lengua

@MainActor
struct YouPageModelTests {
  @Test func titleIsYou() {
    let model = YouPageModel()
    expectNoDifference(model.title, "You")
  }

  @Test func signOutButtonTitleIsSignOut() {
    let model = YouPageModel()
    expectNoDifference(model.signOutButtonTitle, "Sign Out")
  }

  @Test func displayNameAndEmailReflectCurrentUser() {
    @Shared(.auth) var auth = Auth(
      jwtToken: "t",
      currentUser: User(
        id: "1", email: "a@b.com", firstName: "Sam", lastName: nil, profileImageUrl: nil))
    let model = YouPageModel()
    expectNoDifference(model.displayName, "Sam")
    expectNoDifference(model.emailText, "a@b.com")
  }

  @Test func displayNameFallsBackWhenNoName() {
    @Shared(.auth) var auth = Auth()
    let model = YouPageModel()
    expectNoDifference(model.displayName, "Signed in")
    #expect(model.emailText == nil)
  }

  @Test func signOutButtonTappedCallsAuthClientSignOut() async {
    @Shared(.auth) var auth = Auth(jwtToken: "t")
    let signedOut = LockIsolated(false)
    let model = withDependencies {
      $0.authClient.signOut = { signedOut.setValue(true) }
    } operation: {
      YouPageModel()
    }

    await model.signOutButtonTapped()

    #expect(signedOut.value)
  }
}
