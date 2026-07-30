import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class YouPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.authClient) var authClient

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - View Helpers
  var title: String { "You" }
  var signOutButtonTitle: String { "Sign Out" }

  var displayName: String {
    if let firstName = auth.currentUser?.firstName, !firstName.isEmpty {
      return firstName
    }
    return "Signed in"
  }

  var emailText: String? { auth.currentUser?.email }

  // MARK: - User Actions
  func signOutButtonTapped() async {
    await authClient.signOut()
  }
}

struct YouPage: View {
  @State var model: YouPageModel

  var body: some View {
    VStack(spacing: 24) {
      VStack(spacing: 4) {
        Text(model.displayName).font(.title2).bold()
        if let email = model.emailText {
          Text(email).font(.subheadline).foregroundStyle(.secondary)
        }
      }

      Button(model.signOutButtonTitle) {
        Task { await model.signOutButtonTapped() }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(model.title)
  }
}

#Preview {
  NavigationStack {
    YouPage(model: YouPageModel())
  }
}
