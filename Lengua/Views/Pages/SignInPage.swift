import Dependencies
@preconcurrency import GoogleSignIn
import GoogleSignInSwift
import Sharing
import SwiftUI

@MainActor
@Observable
final class SignInPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api
  @ObservationIgnored @Dependency(\.analytics) var analytics
  @ObservationIgnored @Dependency(\.errorReporting) var errorReporting

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var presentedAlert: LenguaAlert?
  let isAppleSignInEnabled = false

  var titleText: String { "Lengua" }
  var subtitleText: String { "Look it up. Keep it. Say it back." }
  var googleSignInButtonTitle: String { "Sign in with Google" }
  var appleSignInButtonTitle: String { "Sign in with Apple" }

  @ObservationIgnored
  var keyWindowProvider: @MainActor () -> UIViewController? = {
    UIApplication.shared.keyWindowPresentedController
  }

  // MARK: - User Actions

  func signInWithGoogleButtonTapped() async {
    await analytics.track(.signInStarted(method: .google))
    guard let presentingVC = keyWindowProvider() else {
      presentedAlert = .signInError
      await errorReporting.reportMessage(
        "Unable to present Google sign-in: no key window",
        ["auth_method": "google", "sign_in_step": "present_view_controller"])
      return
    }
    do {
      let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
      _ = try await signInResult.user.refreshTokensIfNeeded()
      guard let idToken = signInResult.user.idToken?.tokenString else {
        presentedAlert = .signInError
        await errorReporting.reportMessage(
          "Google sign-in missing idToken",
          ["auth_method": "google", "sign_in_step": "id_token"])
        return
      }
      let userId = signInResult.user.userID ?? "unknown"
      let result = try await api.signInViaGoogle(idToken)
      $auth.withLock { $0 = Auth(jwtToken: result.token, currentUser: result.user) }
      await analytics.track(.signInCompleted(method: .google, userId: userId))
    } catch {
      let nsError = error as NSError
      let isUserCancelled =
        nsError.domain == kGIDSignInErrorDomain
        && nsError.code == GIDSignInError.canceled.rawValue
      // Silently drop user-cancelled sign-ins (GIDSignInError.canceled = -5).
      if !isUserCancelled {
        await handleSignInAPIFailure(error, authMethod: .google, step: "google_sign_in_flow")
      }
    }
  }

  // Apple sign-in is intentionally disabled for now (button rendered, no-op).
  func appleSignInButtonTapped() {}

  // MARK: - Internal Helpers

  // Internal so tests can drive alert/analytics/reporting routing directly.
  func handleSignInAPIFailure(_ error: Error, authMethod: AuthMethod, step: String) async {
    presentedAlert =
      NetworkErrorClassifier.isNetworkError(error) ? .signInNetworkError : .signInError
    await analytics.track(.signInFailed(method: authMethod, error: error.localizedDescription))
    let report = SignInErrorReport(error: error, authMethod: authMethod, step: step)
    await errorReporting.reportErrorWithContext(
      error, report.tags, report.contextKey, report.context)
  }
}

struct SignInPage: View {
  @State var model: SignInPageModel

  var body: some View {
    VStack(spacing: 24) {
      Text(model.titleText).font(.largeTitle).bold()
      Text(model.subtitleText).foregroundStyle(.secondary)
      Button(model.googleSignInButtonTitle) {
        Task { await model.signInWithGoogleButtonTapped() }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
