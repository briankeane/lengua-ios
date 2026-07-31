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
  @ObservationIgnored @Shared(.translationProviderKind) var translationProviderKind

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  struct ProviderOption: Identifiable, Equatable {
    let kind: TranslationProviderKind
    let name: String
    let isEnabled: Bool
    let isSelected: Bool
    let disabledNote: String?
    var id: TranslationProviderKind { kind }
  }

  // MARK: - View Helpers
  var title: String { "You" }
  var signOutButtonTitle: String { "Sign Out" }
  var providerSectionTitle: String { "Translation Provider" }

  var displayName: String {
    if let firstName = auth.currentUser?.firstName, !firstName.isEmpty {
      return firstName
    }
    return "Signed in"
  }

  var emailText: String? { auth.currentUser?.email }

  var providerOptions: [ProviderOption] {
    TranslationProviderKind.allCases.map { kind in
      ProviderOption(
        kind: kind,
        name: kind.displayName,
        isEnabled: kind.isEnabled,
        isSelected: kind == translationProviderKind,
        disabledNote: kind.isEnabled ? nil : "Coming soon"
      )
    }
  }

  // MARK: - User Actions
  func signOutButtonTapped() async {
    await authClient.signOut()
  }

  func selectProvider(_ kind: TranslationProviderKind) {
    guard kind.isEnabled else { return }
    $translationProviderKind.withLock { $0 = kind }
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

      VStack(alignment: .leading, spacing: 8) {
        Text(model.providerSectionTitle)
          .font(.subheadline).fontWeight(.semibold)
          .foregroundStyle(.secondary)
        ForEach(model.providerOptions) { option in
          Button {
            model.selectProvider(option.kind)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                if let note = option.disabledNote {
                  Text(note).font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              if option.isSelected {
                Image(systemName: "checkmark").fontWeight(.semibold)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!option.isEnabled)
          .foregroundStyle(option.isEnabled ? Color.primary : Color.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

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
