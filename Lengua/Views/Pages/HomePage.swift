import Sharing
import SwiftUI

@MainActor
@Observable
final class HomePageModel: ViewModel {
  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Properties
  var presentedAlert: LenguaAlert?

  // MARK: - View Helpers
  var navigationTitle: String { "Home" }

  var greeting: String {
    if let firstName = auth.currentUser?.firstName, !firstName.isEmpty {
      return "Hola, \(firstName)!"
    }
    return "Hola!"
  }

  var bodyText: String { "Welcome to Lengua. This is the skeleton home page." }

  // MARK: - User Actions
  override init() { super.init() }

  func viewAppeared() async {
    // Placeholder for future data loading (Stage 3 wires @Dependency(\.api)).
  }
}

struct HomePage: View {
  @State var model: HomePageModel

  var body: some View {
    VStack(spacing: 16) {
      Text(model.greeting).font(.largeTitle).bold()
      Text(model.bodyText).foregroundStyle(.secondary)
    }
    .padding()
    .navigationTitle(model.navigationTitle)
    .lenguaAlert($model.presentedAlert)
    .task { await model.viewAppeared() }
  }
}
