import Sharing
import SwiftUI

@MainActor
@Observable
final class MainContainerModel: ViewModel {
  enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case home
    case profile
  }

  var homeTabTitle: String { "Home" }
  var homeTabIconName: String { "house" }
  var profileTabTitle: String { "Profile" }
  var profileTabIconName: String { "person" }
  var profilePlaceholderText: String { "Profile" }

  override init() { super.init() }
}

struct MainContainer: View {
  @State var model: MainContainerModel
  @Shared(.activeTab) var activeTab
  @Shared(.mainContainerNavigationCoordinator) var coordinator

  var body: some View {
    TabView(selection: Binding($activeTab)) {
      NavigationStack(path: Binding(get: { coordinator.path }, set: { coordinator.path = $0 })) {
        HomePage(model: HomePageModel())
      }
      .tabItem { Label(model.homeTabTitle, systemImage: model.homeTabIconName) }
      .tag(MainContainerModel.ActiveTab.home)

      NavigationStack {
        Text(model.profilePlaceholderText).navigationTitle(model.profileTabTitle)
      }
      .tabItem { Label(model.profileTabTitle, systemImage: model.profileTabIconName) }
      .tag(MainContainerModel.ActiveTab.profile)
    }
  }
}
