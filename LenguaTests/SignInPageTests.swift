import Alamofire
import AuthenticationServices
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@Suite(.serialized)
@MainActor
struct SignInPageTests {
  @Test func displayTextMatchesMockup() {
    @Shared(.auth) var auth = Auth()
    let model = SignInPageModel()
    expectNoDifference(model.titleText, "Lengua")
    expectNoDifference(model.subtitleText, "Look it up. Keep it. Say it back.")
    expectNoDifference(model.googleSignInButtonTitle, "Sign in with Google")
    expectNoDifference(model.appleSignInButtonTitle, "Sign in with Apple")
    #expect(!model.isAppleSignInEnabled)
  }

  @Test func signInWithGoogleTracksSignInStartedEvent() async {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])

    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      $0.errorReporting.reportMessage = { _, _ in }
    } operation: {
      SignInPageModel()
    }
    // Short-circuit before the real Google SDK by returning no key window.
    model.keyWindowProvider = { nil }

    await model.signInWithGoogleButtonTapped()

    #expect(
      capturedEvents.value.contains {
        if case .signInStarted(let method) = $0 { return method == .google }
        return false
      })
  }

  @Test func signInWithGoogleIgnoredWhileAlreadySigningIn() async {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])

    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
    } operation: {
      SignInPageModel()
    }
    model.isSigningIn = true

    await model.signInWithGoogleButtonTapped()

    // The re-entrancy guard returns before any work (no signInStarted tracked).
    #expect(capturedEvents.value.isEmpty)
  }

  @Test func signInWithGooglePresentsAlertWhenNoKeyWindow() async {
    @Shared(.auth) var auth = Auth()
    let reportedMessages = LockIsolated<[String]>([])

    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportMessage = { msg, _ in
        reportedMessages.withValue { $0.append(msg) }
      }
    } operation: {
      SignInPageModel()
    }
    model.keyWindowProvider = { nil }

    await model.signInWithGoogleButtonTapped()

    expectNoDifference(model.presentedAlert, .signInError)
    expectNoDifference(reportedMessages.value.count, 1)
  }

  @Test func handleSignInAPIFailureShowsNetworkAlertOnSSLError() async {
    @Shared(.auth) var auth = Auth()
    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
    } operation: {
      SignInPageModel()
    }

    let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
    let afError = AFError.sessionTaskFailed(error: underlying)

    await model.handleSignInAPIFailure(afError, authMethod: .google, step: "google_sign_in_flow")

    expectNoDifference(model.presentedAlert, .signInNetworkError)
  }

  @Test func handleSignInAPIFailureShowsGenericAlertOnUnknownError() async {
    @Shared(.auth) var auth = Auth()
    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
    } operation: {
      SignInPageModel()
    }

    let genericError = NSError(domain: "com.google.GIDSignIn", code: -4)

    await model.handleSignInAPIFailure(
      genericError, authMethod: .google, step: "google_sign_in_flow")

    expectNoDifference(model.presentedAlert, .signInError)
  }

  @Test func handleSignInAPIFailureTracksAndReportsWithTags() async {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
    let reportedTags = LockIsolated<[String: String]>([:])

    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      $0.errorReporting.reportErrorWithContext = { _, tags, _, _ in
        reportedTags.withValue { $0 = tags }
      }
    } operation: {
      SignInPageModel()
    }

    let genericError = NSError(domain: "com.google.GIDSignIn", code: -4)
    await model.handleSignInAPIFailure(genericError, authMethod: .google, step: "api_call")

    expectNoDifference(reportedTags.value["auth_method"], "google")
    expectNoDifference(reportedTags.value["error_domain"], "com.google.GIDSignIn")
    expectNoDifference(reportedTags.value["error_code"], "-4")
    #expect(
      capturedEvents.value.contains {
        if case .signInFailed(let method, _) = $0 { return method == .google }
        return false
      })
  }

  @Test func signInWithAppleSetsScopesAndTracksStarted() async {
    await withMainSerialExecutor {
      @Shared(.auth) var auth = Auth()
      let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
      let model = withDependencies {
        $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      } operation: {
        SignInPageModel()
      }

      let request = ASAuthorizationAppleIDProvider().createRequest()
      model.signInWithAppleButtonTapped(request: request)

      expectNoDifference(request.requestedScopes, [.email, .fullName])
      await Task.yield()
      #expect(
        capturedEvents.value.contains {
          if case .signInStarted(let method) = $0 { return method == .apple }
          return false
        })
    }
  }

  @Test func completeAppleSignInStoresAuthAndTracksCompletedOnSuccess() async {
    await withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.auth) var auth = Auth()
      let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
      let user = User(
        id: "apple-user-1", email: "sam@example.com", firstName: "Sam",
        lastName: "Lee", profileImageUrl: nil)

      let model = withDependencies {
        $0.api.signInViaApple = { _, _, _, _, _ in
          AppleSignInResult(user: user, token: "jwt-abc")
        }
        $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      } operation: {
        SignInPageModel()
      }

      let payload = AppleSignInPayload(
        identityToken: "id-token", authorizationCode: "auth-code",
        email: "sam@example.com", firstName: "Sam", lastName: "Lee",
        appleUserId: "apple-user-1")

      await model.completeAppleSignIn(payload)

      expectNoDifference(model.auth, Auth(jwtToken: "jwt-abc", currentUser: user))
      #expect(
        capturedEvents.value.contains {
          if case .signInCompleted(let method, let userId) = $0 {
            return method == .apple && userId == "apple-user-1"
          }
          return false
        })
    }
  }

  @Test func completeAppleSignInShowsAlertAndTracksFailureOnAPIError() async {
    await withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.auth) var auth = Auth()
      let capturedEvents = LockIsolated<[AnalyticsEvent]>([])

      let model = withDependencies {
        $0.api.signInViaApple = { _, _, _, _, _ in
          throw NSError(domain: "com.lengua.api", code: 500)
        }
        $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
        $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
      } operation: {
        SignInPageModel()
      }

      let payload = AppleSignInPayload(
        identityToken: "id-token", authorizationCode: "auth-code",
        email: nil, firstName: "", lastName: nil, appleUserId: "apple-user-2")

      await model.completeAppleSignIn(payload)

      expectNoDifference(model.presentedAlert, .signInError)
      expectNoDifference(model.auth.isLoggedIn, false)
      #expect(
        capturedEvents.value.contains {
          if case .signInFailed(let method, _) = $0 { return method == .apple }
          return false
        })
    }
  }

  @Test func completeAppleSignInIgnoredWhileAlreadySigningIn() async {
    await withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.auth) var auth = Auth()
      let apiCalled = LockIsolated(false)

      let model = withDependencies {
        $0.api.signInViaApple = { _, _, _, _, _ in
          apiCalled.setValue(true)
          return AppleSignInResult(
            user: User(
              id: "x", email: "x@x.com", firstName: nil, lastName: nil, profileImageUrl: nil),
            token: "t")
        }
      } operation: {
        SignInPageModel()
      }
      model.isSigningIn = true

      let payload = AppleSignInPayload(
        identityToken: "id-token", authorizationCode: "auth-code",
        email: nil, firstName: "", lastName: nil, appleUserId: "apple-user-3")

      await model.completeAppleSignIn(payload)

      #expect(apiCalled.value == false)
      expectNoDifference(model.auth.isLoggedIn, false)
    }
  }

  @Test func signInWithAppleCompletedCancelledFailureIsSilent() async {
    @Shared(.auth) var auth = Auth()
    let reportCount = LockIsolated(0)

    let model = withDependencies {
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in
        reportCount.withValue { $0 += 1 }
      }
    } operation: {
      SignInPageModel()
    }

    let cancelled = ASAuthorizationError(.canceled)
    await model.signInWithAppleCompleted(result: .failure(cancelled))

    expectNoDifference(model.presentedAlert, nil)
    expectNoDifference(reportCount.value, 0)
  }

  @Test func signInWithAppleCompletedNonCancelFailureShowsAlertAndReports() async {
    @Shared(.auth) var auth = Auth()
    let reportCount = LockIsolated(0)

    let model = withDependencies {
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in
        reportCount.withValue { $0 += 1 }
      }
    } operation: {
      SignInPageModel()
    }

    let failed = ASAuthorizationError(.failed)
    await model.signInWithAppleCompleted(result: .failure(failed))

    expectNoDifference(model.presentedAlert, .signInError)
    expectNoDifference(reportCount.value, 1)
  }
}
