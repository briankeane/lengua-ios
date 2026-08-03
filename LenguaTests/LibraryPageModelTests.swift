import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized, .isolatedSharedState)
struct LibraryPageModelTests {
  private func item(
    id: String, target: String = "x", source: String = "y",
    familiarity: Int = 0, created: TimeInterval = 0
  ) -> VocabItem {
    VocabItem(
      id: id, targetLanguageCode: "es", sourceText: source, targetText: target,
      familiarity: familiarity, lastSeenAt: nil, timesSeen: 0, timesCorrect: 0,
      timesIncorrect: 0, lastOutcome: nil, nextDueAt: nil,
      createdAt: Date(timeIntervalSince1970: created),
      updatedAt: Date(timeIntervalSince1970: created))
  }

  @Test func navigationTitleIsLibrary() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(LibraryPageModel().navigationTitle, "Library")
  }

  @Test func readsLoadingFromSharedState() {
    @Shared(.vocabItems) var vocabItems = VocabItems(isLoading: true)
    expectNoDifference(LibraryPageModel().isLoading, true)
  }

  @Test func emptyStateVisibleWhenLoadedAndEmpty() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = LibraryPageModel()
    expectNoDifference(model.isEmptyStateVisible, true)
    expectNoDifference(model.showsRetry, false)
  }

  @Test func retryVisibleOnFailureWithNoItems() {
    @Shared(.vocabItems) var vocabItems = VocabItems(loadFailed: true)
    let model = LibraryPageModel()
    expectNoDifference(model.showsRetry, true)
    expectNoDifference(model.isEmptyStateVisible, false)
  }

  @Test func retryButtonTappedCallsRefresh() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems()
      return LibraryPageModel()
    }

    await model.retryButtonTapped()

    expectNoDifference(refreshes.value, 1)
  }

  @Test func alphabeticalSortIsCaseInsensitiveByTargetText() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "1", target: "banana"), item(id: "2", target: "Apple"),
        item(id: "3", target: "cherry"),
      ])
    let model = LibraryPageModel()
    model.sortMode = .alphabetical
    expectNoDifference(model.sortedItems.map(\.targetText), ["Apple", "banana", "cherry"])
  }

  @Test func dateSortIsNewestFirst() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "old", created: 100), item(id: "new", created: 300),
        item(id: "mid", created: 200),
      ])
    let model = LibraryPageModel()
    model.sortMode = .date
    expectNoDifference(model.sortedItems.map(\.id), ["new", "mid", "old"])
  }

  @Test func familiaritySortIsAscending() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "known", familiarity: 5), item(id: "new", familiarity: 0),
        item(id: "learning", familiarity: 2),
      ])
    let model = LibraryPageModel()
    model.sortMode = .familiarity
    expectNoDifference(model.sortedItems.map(\.id), ["new", "learning", "known"])
  }

}
