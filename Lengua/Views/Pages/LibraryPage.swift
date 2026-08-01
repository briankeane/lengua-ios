import SwiftUI

@MainActor
@Observable
final class LibraryPageModel: ViewModel {

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - View Helpers
  var navigationTitle: String { "Library" }
}

struct LibraryPage: View {
  @State var model: LibraryPageModel

  var body: some View {
    Text(model.navigationTitle)
      .font(.largeTitle)
      .navigationTitle(model.navigationTitle)
  }
}
