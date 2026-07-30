import SwiftUI

@MainActor
@Observable
final class ReviewPageModel: ViewModel {
  var title: String { "Review" }

  override init() { super.init() }
}

struct ReviewPage: View {
  @State var model: ReviewPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
