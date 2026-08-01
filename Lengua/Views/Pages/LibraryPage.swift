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

  // Palette shared with the Look Up (Translate) page.
  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let cardColor = Color(red: 0.98, green: 0.98, blue: 0.96)

  var body: some View {
    ZStack {
      pageBlue.ignoresSafeArea()

      VStack(spacing: 16) {
        header
        content
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(model.navigationTitle)
        .font(.largeTitle).fontWeight(.bold)
        .foregroundStyle(.white)
      Spacer()
      Menu {
        Picker(model.sortMenuTitle, selection: $model.sortMode) {
          ForEach(model.sortModes, id: \.self) { mode in
            Text(model.sortModeLabel(mode)).tag(mode)
          }
        }
      } label: {
        Label(model.sortMenuTitle, systemImage: "arrow.up.arrow.down")
          .font(.subheadline).fontWeight(.semibold)
          .foregroundStyle(.white)
      }
    }
  }

  @ViewBuilder private var content: some View {
    if model.isLoading {
      Spacer()
      ProgressView().tint(.white)
      Spacer()
    } else if model.showsRetry {
      centeredMessage(model.emptyStateText) {
        Button(model.retryButtonTitle) { Task { await model.retryButtonTapped() } }
          .font(.headline)
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(deepBlue)
      }
    } else if model.isEmptyStateVisible {
      centeredMessage(model.emptyStateText) { EmptyView() }
    } else {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(model.sortedItems) { item in
            LibraryRow(
              targetText: item.targetText,
              sourceText: item.sourceText,
              filledDots: model.familiarityLevel(for: item),
              totalDots: model.familiarityMaxLevel,
              deepBlue: deepBlue,
              cardColor: cardColor)
          }
        }
        .padding(.bottom, 16)
      }
    }
  }

  private func centeredMessage<Action: View>(
    _ text: String, @ViewBuilder action: () -> Action
  ) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "books.vertical")
        .font(.system(size: 44))
        .foregroundStyle(.white.opacity(0.7))
      Text(text)
        .font(.body)
        .foregroundStyle(.white.opacity(0.85))
        .multilineTextAlignment(.center)
      action()
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

private struct LibraryRow: View {
  let targetText: String
  let sourceText: String
  let filledDots: Int
  let totalDots: Int
  let deepBlue: Color
  let cardColor: Color

  private var dotsColumnWidth: CGFloat { CGFloat(totalDots) * 7 + CGFloat(totalDots - 1) * 3 }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Target and source share the row evenly so the columns line up across
      // rows; text wraps (growing the card vertically) instead of truncating.
      Text(targetText)
        .font(.headline)
        .foregroundStyle(deepBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Text(sourceText)
        .font(.subheadline)
        .foregroundStyle(deepBlue.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 3) {
        ForEach(0..<totalDots, id: \.self) { index in
          Circle()
            .fill(index < filledDots ? deepBlue : deepBlue.opacity(0.18))
            .frame(width: 7, height: 7)
        }
      }
      .frame(width: dotsColumnWidth, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16).fill(cardColor))
  }
}
