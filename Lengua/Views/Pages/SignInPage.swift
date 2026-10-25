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

  var titleText: String { "Lengua" }
  var subtitleText: String { "Look it up. Keep it. Say it back." }
  var googleSignInButtonTitle: String { "Sign in with Google" }

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

  // Called synchronously by `SignInWithAppleButton` before Apple's sheet is shown.
  func signInWithAppleButtonTapped(request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.fullName, .email]
    isSigningIn = true
  }

  func signInWithAppleCompleted(result: Result<ASAuthorization, any Error>) async {
    defer { isSigningIn = false }
    await analytics.track(.signInStarted(method: .apple))

    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let identityTokenData = credential.identityToken,
        let identityToken = String(data: identityTokenData, encoding: .utf8)
      else {
        presentedAlert = .signInError
        await errorReporting.reportMessage(
          "Apple sign-in missing identityToken",
          ["auth_method": "apple", "sign_in_step": "identity_token"])
        return
      }
      await exchangeAppleIdentityToken(
        identityToken, fullName: credential.fullName, appleUserId: credential.user)
    case .failure(let error):
      let isUserCancelled = (error as? ASAuthorizationError)?.code == .canceled
      if !isUserCancelled {
        await handleSignInAPIFailure(error, authMethod: .apple, step: "apple_authorization")
      }
    }
  }

  // MARK: - Internal Helpers

  // Internal so tests can drive the server exchange without fabricating an ASAuthorization.
  // Apple only returns `fullName` on the first authorization; the server keeps it from then on.
  func exchangeAppleIdentityToken(
    _ identityToken: String, fullName: PersonNameComponents?, appleUserId: String
  ) async {
    do {
      let result = try await api.signInViaApple(
        identityToken, fullName?.givenName, fullName?.familyName)
      $auth.withLock { $0 = Auth(jwtToken: result.token, currentUser: result.user) }
      await analytics.track(.signInCompleted(method: .apple, userId: appleUserId))
    } catch {
      await handleSignInAPIFailure(error, authMethod: .apple, step: "api_call")
    }
  }

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
            title: model.googleSignInButtonTitle
          ) {
            Task { await model.signInWithGoogleButtonTapped() }
          }
          .disabled(model.isSigningIn)
          .opacity(model.isSigningIn ? 0.5 : 1)

          SignInWithAppleButton(.signIn) { request in
            model.signInWithAppleButtonTapped(request: request)
          } onCompletion: { result in
            Task { await model.signInWithAppleCompleted(result: result) }
          }
          .signInWithAppleButtonStyle(.white)
          .frame(height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .disabled(model.isSigningIn)
          .opacity(model.isSigningIn ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
    }
    .lenguaAlert($model.presentedAlert)
  }
}

private struct WhiteSignInButton: View {
  let iconImageName: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(iconImageName)
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
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
