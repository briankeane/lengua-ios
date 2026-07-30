import Sharing
import SwiftUI

@MainActor
@Observable
final class MainContainerModel: ViewModel {
  enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case home
    case profile
  }

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
      .tabItem { Label("Home", systemImage: "house") }
      .tag(MainContainerModel.ActiveTab.home)

      NavigationStack {
        Text("Profile").navigationTitle("Profile")
      }
      .tabItem { Label("Profile", systemImage: "person") }
      .tag(MainContainerModel.ActiveTab.profile)
    }
  }
}
