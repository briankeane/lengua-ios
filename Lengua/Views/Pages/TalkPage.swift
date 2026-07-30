import SwiftUI

@MainActor
@Observable
final class TalkPageModel: ViewModel {
  var title: String { "Talk" }

  override init() { super.init() }
}

struct TalkPage: View {
  @State var model: TalkPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
