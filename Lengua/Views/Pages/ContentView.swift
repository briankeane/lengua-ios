import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ContentViewModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - View Helpers
  var isLoggedIn: Bool { auth.isLoggedIn }

  // MARK: - User Actions
  func authStateChanged() async {
    if auth.isLoggedIn {
      await vocabItemsClient.refresh()
    } else {
      vocabItemsClient.clear()
    }
  }

  func appEnteredForeground() async {
    guard auth.isLoggedIn else { return }
    await vocabItemsClient.refresh()
  }
}

@MainActor
struct ContentView: View {
  @State var model = ContentViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var mainContainerModel = MainContainerModel()
  var signInModel = SignInPageModel()

  var body: some View {
    Group {
      if model.isLoggedIn {
        MainContainer(model: mainContainerModel)
      } else {
        SignInPage(model: signInModel)
      }
    }
    .translatorHost()
    .task(id: model.isLoggedIn) { await model.authStateChanged() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.appEnteredForeground() }
      }
    }
  }
}
