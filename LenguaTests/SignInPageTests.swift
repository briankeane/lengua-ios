import Alamofire
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import XCTest

@testable import Lengua

@MainActor
final class SignInPageTests: XCTestCase {
  func testDisplayTextMatchesMockup() {
    @Shared(.auth) var auth = Auth()
    let model = SignInPageModel()
    XCTAssertEqual(model.titleText, "Lengua")
    XCTAssertEqual(model.subtitleText, "Look it up. Keep it. Say it back.")
    XCTAssertEqual(model.googleSignInButtonTitle, "Sign in with Google")
    XCTAssertEqual(model.appleSignInButtonTitle, "Sign in with Apple")
    XCTAssertFalse(model.isAppleSignInEnabled)
  }

  func testSignInWithGoogleTracksSignInStartedEvent() async {
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

    XCTAssertTrue(
      capturedEvents.value.contains {
        if case .signInStarted(let method) = $0 { return method == .google }
        return false
      })
  }

  func testSignInWithGooglePresentsAlertWhenNoKeyWindow() async {
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
    XCTAssertEqual(reportedMessages.value.count, 1)
  }

  func testHandleSignInAPIFailureShowsNetworkAlertOnSSLError() async {
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

  func testHandleSignInAPIFailureShowsGenericAlertOnUnknownError() async {
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

  func testHandleSignInAPIFailureTracksAndReportsWithTags() async {
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

    XCTAssertEqual(reportedTags.value["auth_method"], "google")
    XCTAssertEqual(reportedTags.value["error_domain"], "com.google.GIDSignIn")
    XCTAssertEqual(reportedTags.value["error_code"], "-4")
    XCTAssertTrue(
      capturedEvents.value.contains {
        if case .signInFailed(let method, _) = $0 { return method == .google }
        return false
      })
  }
}
