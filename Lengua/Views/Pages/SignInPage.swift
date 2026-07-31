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
      guard let serverAuthCode = signInResult.serverAuthCode else {
        presentedAlert = .signInError
        await errorReporting.reportMessage(
          "Google sign-in missing serverAuthCode",
          ["auth_method": "google", "sign_in_step": "server_auth_code"])
        return
      }
      let userId = signInResult.user.userID ?? "unknown"
      let result = try await api.signInViaGoogle(serverAuthCode)
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
  @Bindable var model: SignInPageModel

  var body: some View {
    ZStack {
      Color(red: 0.24, green: 0.29, blue: 0.85)
        .ignoresSafeArea()

      VStack(spacing: 24) {
        Spacer()

        Image("LogoMark")
          .resizable()
          .scaledToFit()
          .frame(height: 96)

        Text(model.titleText)
          .font(.system(size: 56, weight: .bold))
          .foregroundStyle(.white)

        Text(model.subtitleText)
          .font(.title3)
          .foregroundStyle(.white.opacity(0.75))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 48)

        Spacer()

        VStack(spacing: 16) {
          WhiteSignInButton(
            iconImageName: "google-icon",
            systemIcon: nil,
            title: model.googleSignInButtonTitle
          ) {
            Task { await model.signInWithGoogleButtonTapped() }
          }

          WhiteSignInButton(
            iconImageName: nil,
            systemIcon: "apple.logo",
            title: model.appleSignInButtonTitle
          ) {
            model.appleSignInButtonTapped()
          }
          .disabled(!model.isAppleSignInEnabled)
          .opacity(model.isAppleSignInEnabled ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
    }
    .lenguaAlert($model.presentedAlert)
  }
}

private struct WhiteSignInButton: View {
  let iconImageName: String?
  let systemIcon: String?
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let iconImageName {
          Image(iconImageName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
        } else if let systemIcon {
          Image(systemName: systemIcon)
            .font(.system(size: 22))
            .foregroundStyle(.black)
        }
        Text(title)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.black)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }
}

#Preview {
  SignInPage(model: SignInPageModel())
}
