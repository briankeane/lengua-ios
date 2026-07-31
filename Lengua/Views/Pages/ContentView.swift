import Sharing
import SwiftUI

@MainActor
struct ContentView: View {
  @Shared(.auth) var auth

  var mainContainerModel = MainContainerModel()
  var signInModel = SignInPageModel()

  var body: some View {
    Group {
      if auth.isLoggedIn {
        MainContainer(model: mainContainerModel)
      } else {
        SignInPage(model: signInModel)
      }
    }
    .translatorHost()
  }
}
