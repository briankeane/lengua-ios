import Sharing
import SwiftUI

@MainActor
@Observable
final class MainContainerModel: ViewModel {
  enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case lookUp
    case library
    case review
    case talk
    case you
  }

  var lookUpTabTitle: String { "Look up" }
  var lookUpTabIconName: String { "magnifyingglass" }
  var libraryTabTitle: String { "Library" }
  var libraryTabIconName: String { "books.vertical" }
  var reviewTabTitle: String { "Review" }
  var reviewTabIconName: String { "checkmark.square" }
  var talkTabTitle: String { "Talk" }
  var talkTabIconName: String { "waveform" }
  var youTabTitle: String { "You" }
  var youTabIconName: String { "person" }

  override init() { super.init() }
}

struct MainContainer: View {
  @State var model: MainContainerModel
  @Shared(.activeTab) var activeTab

  var body: some View {
    TabView(selection: Binding($activeTab)) {
      NavigationStack {
        TranslatePage(model: TranslatePageModel())
      }
      .tabItem { Label(model.lookUpTabTitle, systemImage: model.lookUpTabIconName) }
      .tag(MainContainerModel.ActiveTab.lookUp)

      NavigationStack {
        LibraryPage(model: LibraryPageModel())
      }
      .tabItem { Label(model.libraryTabTitle, systemImage: model.libraryTabIconName) }
      .tag(MainContainerModel.ActiveTab.library)

      NavigationStack {
        ReviewPage(model: ReviewPageModel())
      }
      .tabItem { Label(model.reviewTabTitle, systemImage: model.reviewTabIconName) }
      .tag(MainContainerModel.ActiveTab.review)

      NavigationStack {
        TalkPage(model: TalkPageModel())
      }
      .tabItem { Label(model.talkTabTitle, systemImage: model.talkTabIconName) }
      .tag(MainContainerModel.ActiveTab.talk)

      NavigationStack {
        YouPage(model: YouPageModel())
      }
      .tabItem { Label(model.youTabTitle, systemImage: model.youTabIconName) }
      .tag(MainContainerModel.ActiveTab.you)
    }
  }
}
