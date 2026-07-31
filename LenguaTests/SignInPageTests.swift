import Alamofire
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

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
}
