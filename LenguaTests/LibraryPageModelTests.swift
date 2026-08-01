import CustomDump
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct LibraryPageModelTests {
  @Test func navigationTitleIsLibrary() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(LibraryPageModel().navigationTitle, "Library")
  }
}
