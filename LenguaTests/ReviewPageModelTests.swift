import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized) struct ReviewPageModelTests {
  @Test func navigationTitleIsReview() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(ReviewPageModel().navigationTitle, "Review")
  }

  @Test func modeMapsToDirection() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewPageModel()
    model.mode = .adaptive
    expectNoDifference(model.direction, nil)
    model.mode = .recognition
    expectNoDifference(model.direction, .receptive)
    model.mode = .production
    expectNoDifference(model.direction, .productive)
  }

  @Test func dueSummaryPluralizesAndReportsCaughtUp() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 1, productive: 3, total: 4))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    await model.viewAppeared()
    expectNoDifference(model.dueSummary, "1 to recognize · 3 to produce")

    let caughtUpModel = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    await caughtUpModel.viewAppeared()
    expectNoDifference(caughtUpModel.dueSummary, "All caught up 🎉")
  }

  @Test func emptyStateDistinguishesNoWordsFromNoneDue() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()  // no items

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    await model.viewAppeared()
    expectNoDifference(model.noWordsSaved, true)
    expectNoDifference(model.emptyStateText, "Save some words to review them here.")

    $vocabItems.withLock {
      $0.items[id: "a"] = VocabItem(
        id: "a", targetLanguageCode: "es", sourceText: "s", targetText: "t")
    }

    let model2 = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    await model2.viewAppeared()
    expectNoDifference(model2.noWordsSaved, false)
    expectNoDifference(model2.emptyStateText, "You're all caught up — check back later.")
  }

  @Test func showsEmptyStateWaitsForFirstFetchThenReflectsZeroCounts() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    expectNoDifference(model.showsEmptyState, false)

    await model.viewAppeared()
    expectNoDifference(model.showsEmptyState, true)
  }

  @Test func fetchFailureSetsLoadFailedAndRetrySucceedsClearsIt() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let attempts = LockIsolated(0)

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        attempts.withValue { $0 += 1 }
        if attempts.value == 1 { throw APIError.dataNotValid }
        return ReviewQueue(
          cards: [], dueCounts: DueCounts(receptive: 1, productive: 0, total: 1))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }

    await model.viewAppeared()
    expectNoDifference(model.loadFailed, true)
    expectNoDifference(model.isLoading, false)

    await model.retryButtonTapped()
    expectNoDifference(model.loadFailed, false)
    expectNoDifference(model.isLoading, false)
  }

  @Test func startCreatesSessionOnlyWhenBatchNonEmpty() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let card = ReviewCard(
      vocabItemId: "a", sourceText: "s", targetText: "t",
      targetLanguageCode: "es", direction: .receptive, familiarity: 0, nextDueAt: nil)

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [card], dueCounts: DueCounts(receptive: 1, productive: 0, total: 1))
      }
    } operation: {
      ReviewPageModel()
    }
    await model.startReviewingButtonTapped()
    #expect(model.session != nil)

    let emptyModel = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
    } operation: {
      ReviewPageModel()
    }
    await emptyModel.startReviewingButtonTapped()
    #expect(emptyModel.session == nil)
  }

  @Test func viewAppearedRefreshesVocabItemsCache() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let refreshes = LockIsolated(0)

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0))
      }
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      ReviewPageModel()
    }

    await model.viewAppeared()

    expectNoDifference(refreshes.value, 1)
  }

  @Test func selectedModeDueCountReflectsModeWhenOtherTrackHasNoneDue() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()

    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in
        ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 3, total: 3))
      }
      $0.vocabItemsClient.refresh = {}
    } operation: {
      ReviewPageModel()
    }
    await model.viewAppeared()

    model.mode = .recognition
    expectNoDifference(model.selectedModeDueCount, 0)
    expectNoDifference(model.canStartReview, false)
    expectNoDifference(
      model.modeEmptyHint, "Nothing to recognize right now — try Adaptive or Production.")

    model.mode = .production
    expectNoDifference(model.selectedModeDueCount, 3)
    expectNoDifference(model.canStartReview, true)
    expectNoDifference(model.modeEmptyHint, nil)

    model.mode = .adaptive
    expectNoDifference(model.selectedModeDueCount, 3)
    expectNoDifference(model.canStartReview, true)
    expectNoDifference(model.modeEmptyHint, nil)
  }

  @Test func hubStringHelpersAreStable() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewPageModel()
    expectNoDifference(model.modePickerLabel, "Review Mode")
    expectNoDifference(
      model.loadFailedText, "Something went wrong loading your review queue.")
  }
}
