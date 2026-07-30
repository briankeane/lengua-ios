import Sharing
import SwiftUI

@MainActor
@Observable
final class SignInPageModel: ViewModel {
  @ObservationIgnored @Shared(.auth) var auth

  var titleText: String { "Lengua" }
  var subtitleText: String { "Sign in to get started." }
  var signInButtonTitle: String { "Sign In" }

  override init() { super.init() }

  // Placeholder: real Apple/Google sign-in providers are built later.
  // For skeleton bring-up this is a no-op stub.
  func signInButtonTapped() {
    // TODO(auth): implement real sign-in and set $auth.
  }
}

struct SignInPage: View {
  @State var model: SignInPageModel

  var body: some View {
    VStack(spacing: 24) {
      Text(model.titleText).font(.largeTitle).bold()
      Text(model.subtitleText).foregroundStyle(.secondary)
      Button(model.signInButtonTitle) { model.signInButtonTapped() }
        .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
