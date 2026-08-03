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
      receptiveFamiliarity: familiarity,
      createdAt: Date(timeIntervalSince1970: created))
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

  @Test func familiaritySortOrdersByWeakestThenStrongestSkill() {
    func item(id: String, receptive: Int, productive: Int) -> VocabItem {
      VocabItem(
        id: id, targetLanguageCode: "es", sourceText: "y", targetText: "x",
        receptiveFamiliarity: receptive, productiveFamiliarity: productive)
    }
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "even", receptive: 3, productive: 3),  // key (3,3)
        item(id: "weakHighMax", receptive: 5, productive: 1),  // key (1,5)
        item(id: "zero", receptive: 0, productive: 0),  // key (0,0)
        item(id: "weakLowMax", receptive: 1, productive: 4),  // key (1,4)
      ])
    let model = LibraryPageModel()
    model.sortMode = .familiarity
    expectNoDifference(
      model.sortedItems.map(\.id),
      ["zero", "weakLowMax", "weakHighMax", "even"])
  }

  @Test func familiaritySortModeLabelIsWeakestSkill() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(LibraryPageModel().sortModeLabel(.familiarity), "Weakest skill")
  }

  @Test func deleteButtonTappedRemovesItem() async {
    let deleted = LockIsolated<[String]>([])
    let model = withDependencies {
      $0.vocabItemsClient.delete = { id in
        deleted.withValue { $0.append(id) }
        @Shared(.vocabItems) var vocabItems
        $vocabItems.withLock { _ = $0.items.remove(id: id) }
      }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(
        items: [item(id: "1"), item(id: "2")])
      return LibraryPageModel()
    }

    await model.deleteButtonTapped(item(id: "1"))

    expectNoDifference(deleted.value, ["1"])
    expectNoDifference(model.sortedItems.map(\.id), ["2"])
    expectNoDifference(model.presentedAlert, nil)
  }

  @Test func deleteFailureShowsAlertAndKeepsItem() async {
    let model = withDependencies {
      $0.vocabItemsClient.delete = { _ in throw APIError.dataNotValid }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      return LibraryPageModel()
    }

    await model.deleteButtonTapped(item(id: "1"))

    expectNoDifference(model.presentedAlert, .deleteFailed)
    expectNoDifference(model.sortedItems.map(\.id), ["1"])
    expectNoDifference(model.isDeleting("1"), false)
  }

  @Test func deleteButtonTappedIsGuardedAgainstDuplicateTaps() async {
    let callCount = LockIsolated(0)
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    let model = withDependencies {
      $0.vocabItemsClient.delete = { _ in
        callCount.withValue { $0 += 1 }
        started.continuation.yield()  // signal the first delete is genuinely in flight
        var iterator = release.stream.makeAsyncIterator()
        _ = await iterator.next()  // hold the first delete in flight
      }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      return LibraryPageModel()
    }

    async let first: Void = model.deleteButtonTapped(item(id: "1"))
    // Wait until the first delete has actually begun (id inserted, closure entered)
    // rather than racing on Task.yield() timing.
    var startedIterator = started.stream.makeAsyncIterator()
    _ = await startedIterator.next()
    expectNoDifference(model.isDeleting("1"), true)

    await model.deleteButtonTapped(item(id: "1"))  // second tap: guarded no-op
    expectNoDifference(callCount.value, 1)

    release.continuation.yield()
    await first
    expectNoDifference(model.isDeleting("1"), false)
  }

}
