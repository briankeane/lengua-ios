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
    List {
      ForEach(model.sortedItems) { item in
        LibraryRow(
          targetText: item.targetText,
          sourceText: item.sourceText,
          filledDots: model.familiarityLevel(for: item),
          totalDots: model.familiarityMaxLevel)
      }
    }
    .overlay {
      if model.isLoading {
        ProgressView()
      } else if model.showsRetry {
        RetryState(message: model.emptyStateText, buttonTitle: model.retryButtonTitle) {
          await model.retryButtonTapped()
        }
      } else if model.isEmptyStateVisible {
        ContentUnavailableView(model.emptyStateText, systemImage: "books.vertical")
      }
    }
    .navigationTitle(model.navigationTitle)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu(model.sortMenuTitle) {
          Picker(model.sortMenuTitle, selection: $model.sortMode) {
            ForEach(model.sortModes, id: \.self) { mode in
              Text(model.sortModeLabel(mode)).tag(mode)
            }
          }
        }
      }
    }
  }
}

private struct LibraryRow: View {
  let targetText: String
  let sourceText: String
  let filledDots: Int
  let totalDots: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(targetText).font(.headline)
        Text(sourceText).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      HStack(spacing: 3) {
        ForEach(0..<totalDots, id: \.self) { index in
          Circle()
            .fill(index < filledDots ? Color.accentColor : Color.secondary.opacity(0.25))
            .frame(width: 7, height: 7)
        }
      }
    }
  }
}

private struct RetryState: View {
  let message: String
  let buttonTitle: String
  let retry: () async -> Void

  var body: some View {
    ContentUnavailableView {
      Label(message, systemImage: "exclamationmark.triangle")
    } actions: {
      Button(buttonTitle) { Task { await retry() } }
    }
  }
}
