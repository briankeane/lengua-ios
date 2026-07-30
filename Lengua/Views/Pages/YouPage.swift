import SwiftUI

@MainActor
@Observable
final class YouPageModel: ViewModel {
  var title: String { "You" }

  override init() { super.init() }
}

struct YouPage: View {
  @State var model: YouPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
