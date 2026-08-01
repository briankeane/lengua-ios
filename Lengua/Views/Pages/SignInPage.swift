import AuthenticationServices
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
  var isSigningIn = false
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
    // Ignore taps while a sign-in is already in flight to avoid overlapping
    // SDK presentations and duplicate server exchanges.
    guard !isSigningIn else { return }
    isSigningIn = true
    defer { isSigningIn = false }

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

  func signInWithAppleButtonTapped(request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.email, .fullName]
    Task { await analytics.track(.signInStarted(method: .apple)) }
  }

  func signInWithAppleCompleted(result: Result<ASAuthorization, any Error>) async {
    switch result {
    case .success(let authorization):
      let payload: AppleSignInPayload
      do {
        payload = try decodeAppleAuthorization(authorization)
      } catch {
        await handleAppleCredentialDecodeFailure(error)
        return
      }
      await completeAppleSignIn(payload)
    case .failure(let error):
      await handleAppleAuthorizationFailure(error)
    }
  }

  func completeAppleSignIn(_ payload: AppleSignInPayload) async {
    // Only one sign-in at a time across Google and Apple.
    guard !isSigningIn else { return }
    isSigningIn = true
    defer { isSigningIn = false }

    do {
      let result = try await api.signInViaApple(
        payload.identityToken, payload.email, payload.authorizationCode,
        payload.firstName, payload.lastName)
      $auth.withLock { $0 = Auth(jwtToken: result.token, currentUser: result.user) }
      await analytics.track(.signInCompleted(method: .apple, userId: payload.appleUserId))
    } catch {
      await handleSignInAPIFailure(error, authMethod: .apple, step: "api_call")
    }
  }

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

  func handleAppleCredentialDecodeFailure(_ error: any Error) async {
    presentedAlert = .signInError
    await errorReporting.reportMessage(
      "Error decoding sign-in info from Apple",
      [
        "auth_method": "apple",
        "sign_in_step": "credential_decode",
        "decode_reason": (error as? AppleCredentialDecodeError)?.rawValue ?? "unknown",
      ])
  }

  // Thin extraction of the Apple credential. The only piece not unit-tested,
  // because ASAuthorization / ASAuthorizationAppleIDCredential cannot be
  // constructed in tests. Throws a specific case so decode failures are
  // diagnosable in error reports.
  func decodeAppleAuthorization(_ authorization: ASAuthorization) throws -> AppleSignInPayload {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      throw AppleCredentialDecodeError.notAppleIDCredential
    }
    guard let identityTokenData = credential.identityToken else {
      throw AppleCredentialDecodeError.missingIdentityToken
    }
    guard let identityToken = String(data: identityTokenData, encoding: .utf8) else {
      throw AppleCredentialDecodeError.identityTokenNotUTF8
    }
    guard let authCodeData = credential.authorizationCode else {
      throw AppleCredentialDecodeError.missingAuthorizationCode
    }
    guard let authorizationCode = String(data: authCodeData, encoding: .utf8) else {
      throw AppleCredentialDecodeError.authorizationCodeNotUTF8
    }
    return AppleSignInPayload(
      identityToken: identityToken,
      authorizationCode: authorizationCode,
      email: credential.email,
      firstName: credential.fullName?.givenName ?? "",
      lastName: credential.fullName?.familyName,
      appleUserId: credential.user)
  }

  // MARK: - Private Helpers

  private func handleAppleAuthorizationFailure(_ error: any Error) async {
    // The user tapping "Cancel" on the system sheet is not an error.
    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      return
    }
    presentedAlert = .signInError
    let report = SignInErrorReport(error: error, authMethod: .apple, step: "authorization_failure")
    await errorReporting.reportErrorWithContext(
      error, report.tags, report.contextKey, report.context)
  }
}

struct AppleSignInPayload: Equatable {
  let identityToken: String
  let authorizationCode: String
  let email: String?
  let firstName: String
  let lastName: String?
  let appleUserId: String
}

enum AppleCredentialDecodeError: String, Error {
  case notAppleIDCredential
  case missingIdentityToken
  case identityTokenNotUTF8
  case missingAuthorizationCode
  case authorizationCodeNotUTF8
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
          .disabled(model.isSigningIn)
          .opacity(model.isSigningIn ? 0.5 : 1)

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
