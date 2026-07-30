import SwiftUI

@MainActor
@Observable
final class DeckPageModel: ViewModel {
  var title: String { "Deck" }

  override init() { super.init() }
}

struct DeckPage: View {
  @State var model: DeckPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
