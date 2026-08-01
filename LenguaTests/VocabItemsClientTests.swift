import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import IdentifiedCollections
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct VocabItemsClientTests {
  private nonisolated func item(id: String, familiarity: Int = 0) -> VocabItem {
    VocabItem(
      id: id, targetLanguageCode: "es", sourceText: "s", targetText: "t",
      familiarity: familiarity, lastSeenAt: nil, timesSeen: 0, timesCorrect: 0,
      timesIncorrect: 0, lastOutcome: nil, nextDueAt: nil,
      createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
  }

  @Test func refreshLoadsAllPagesIntoSharedState() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, cursor in
        cursor == nil
          ? VocabItemsPage(items: [self.item(id: "1")], nextCursor: "c2")
          : VocabItemsPage(items: [self.item(id: "2")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.items.map(\.id), ["1", "2"])
      expectNoDifference(vocabItems.isLoading, false)
      expectNoDifference(vocabItems.loadFailed, false)
    }
  }

  @Test func refreshFailureSetsLoadFailed() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw APIError.dataNotValid }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.loadFailed, true)
      expectNoDifference(vocabItems.isLoading, false)
      expectNoDifference(vocabItems.items.isEmpty, true)
    }
  }

  @Test func refreshCancellationDoesNotSetLoadFailed() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw CancellationError() }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.loadFailed, false)
      expectNoDifference(vocabItems.isLoading, false)
    }
  }

  @Test func refreshDiscardsResultsIfSignedOutMidLoad() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        @Shared(.auth) var auth
        $auth.withLock { $0 = Auth() }  // sign out during the load
        return VocabItemsPage(items: [self.item(id: "1")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.items.isEmpty, true)
      expectNoDifference(vocabItems.isLoading, false)
    }
  }

  @Test func refreshIsCoalescedWhileAlreadyLoading() async {
    let callCount = LockIsolated(0)
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        callCount.withValue { $0 += 1 }
        return VocabItemsPage(items: [self.item(id: "1")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(isLoading: true)  // pretend a load is in flight
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()  // should no-op because isLoading == true

      expectNoDifference(callCount.value, 0)
    }
  }

  @Test func clearResetsSharedState() {
    withDependencies {
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(
        items: [item(id: "1")], isLoading: true, loadFailed: true)
      @Dependency(\.vocabItemsClient) var client

      client.clear()

      expectNoDifference(vocabItems, VocabItems())
    }
  }
}
