import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct ContentViewModelTests {
  @Test func authStateChangedRefreshesWhenLoggedIn() async {
    let refreshes = LockIsolated(0)
    let clears = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
      $0.vocabItemsClient.clear = { clears.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      return ContentViewModel()
    }

    await model.authStateChanged()

    expectNoDifference(refreshes.value, 1)
    expectNoDifference(clears.value, 0)
  }

  @Test func authStateChangedClearsWhenLoggedOut() async {
    let refreshes = LockIsolated(0)
    let clears = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
      $0.vocabItemsClient.clear = { clears.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth()
      return ContentViewModel()
    }

    await model.authStateChanged()

    expectNoDifference(clears.value, 1)
    expectNoDifference(refreshes.value, 0)
  }

  @Test func foregroundRefreshesWhenLoggedIn() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      return ContentViewModel()
    }

    await model.appEnteredForeground()

    expectNoDifference(refreshes.value, 1)
  }

  @Test func foregroundIsNoOpWhenLoggedOut() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth()
      return ContentViewModel()
    }

    await model.appEnteredForeground()

    expectNoDifference(refreshes.value, 0)
  }

  @Test func isLoggedInReflectsAuth() {
    @Shared(.auth) var auth = Auth(jwtToken: "t")
    expectNoDifference(ContentViewModel().isLoggedIn, true)
  }
}
