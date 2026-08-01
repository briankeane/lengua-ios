import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class LibraryPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var sortMode: SortMode = .date

  enum SortMode: String, CaseIterable, Sendable {
    case date
    case alphabetical
    case familiarity
  }

  // MARK: - User Actions
  func retryButtonTapped() async {
    await vocabItemsClient.refresh()
  }

  // MARK: - View Helpers
  var navigationTitle: String { "Library" }
  var emptyStateText: String { "You haven't saved any vocab items yet." }
  var retryButtonTitle: String { "Try Again" }
  var sortMenuTitle: String { "Sort" }

  var sortModes: [SortMode] { SortMode.allCases }

  func sortModeLabel(_ mode: SortMode) -> String {
    switch mode {
    case .date: return "Date"
    case .alphabetical: return "Alphabetical"
    case .familiarity: return "Familiarity"
    }
  }

  var isLoading: Bool { vocabItems.isLoading }
  var isEmptyStateVisible: Bool {
    !vocabItems.isLoading && !vocabItems.loadFailed && vocabItems.items.isEmpty
  }
  var showsRetry: Bool { vocabItems.loadFailed && vocabItems.items.isEmpty }

  let familiarityMaxLevel = 5

  func familiarityLevel(for item: VocabItem) -> Int {
    min(max(item.familiarity, 0), familiarityMaxLevel)
  }

  var sortedItems: [VocabItem] {
    switch sortMode {
    case .date:
      return vocabItems.items.sorted { lhs, rhs in
        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id > rhs.id
      }
    case .alphabetical:
      return vocabItems.items.sorted { lhs, rhs in
        let byTarget = lhs.targetText.localizedCaseInsensitiveCompare(rhs.targetText)
        if byTarget != .orderedSame { return byTarget == .orderedAscending }
        let bySource = lhs.sourceText.localizedCaseInsensitiveCompare(rhs.sourceText)
        if bySource != .orderedSame { return bySource == .orderedAscending }
        return lhs.id < rhs.id
      }
    case .familiarity:
      return vocabItems.items.sorted { lhs, rhs in
        lhs.familiarity != rhs.familiarity
          ? lhs.familiarity < rhs.familiarity
          : lhs.createdAt > rhs.createdAt
      }
    }
  }
}

struct LibraryPage: View {
  @State var model: LibraryPageModel

  var body: some View {
    Text(model.navigationTitle)
      .font(.largeTitle)
      .navigationTitle(model.navigationTitle)
  }
}
