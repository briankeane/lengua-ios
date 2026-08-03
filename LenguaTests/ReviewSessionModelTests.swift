import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized) struct ReviewSessionModelTests {
  private nonisolated func card(_ id: String, _ dir: ReviewDirection = .receptive) -> ReviewCard {
    ReviewCard(
      vocabItemId: id, sourceText: "s-\(id)", targetText: "t-\(id)",
      targetLanguageCode: "es", direction: dir, familiarity: 0, nextDueAt: nil)
  }
  private nonisolated func stubItem(_ id: String) -> VocabItem {
    VocabItem(id: id, targetLanguageCode: "es", sourceText: "s", targetText: "t")
  }

  @Test func correctAdvancesAndClears() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b")])
    }
    await model.gotItButtonTapped()
    expectNoDifference(model.current?.vocabItemId, "b")
    expectNoDifference(model.clearedCount, 1)
    expectNoDifference(model.resolvedCount, 1)
  }

  @Test func incorrectRequeuesAndStaysUntilCorrect() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b")])
    }
    await model.missedItButtonTapped()  // a missed -> reinserted (queue.count small -> at end)
    expectNoDifference(model.current?.vocabItemId, "b")
    expectNoDifference(model.clearedCount, 0)
    await model.gotItButtonTapped()  // b correct
    expectNoDifference(model.current?.vocabItemId, "a")  // a came back
    expectNoDifference(model.isFinished, false)
  }

  @Test func cardDroppedAfterThreeMisses() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: {
      ReviewSessionModel(cards: [card("a")])
    }
    await model.missedItButtonTapped()  // miss 1 -> reinsert (only card)
    await model.missedItButtonTapped()  // miss 2 -> reinsert
    await model.missedItButtonTapped()  // miss 3 -> drop
    expectNoDifference(model.isFinished, true)
    expectNoDifference(model.resolvedCount, 1)  // counts toward progress denominator
    expectNoDifference(model.clearedCount, 0)
  }

  @Test func submitFailureKeepsCardAndRetryResends() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let attempts = LockIsolated(0)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in
        attempts.withValue { $0 += 1 }
        if attempts.value == 1 { throw APIError.dataNotValid }
        return stubItem(id)
      }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b")])
    }
    await model.gotItButtonTapped()
    expectNoDifference(model.submitFailed, true)
    expectNoDifference(model.current?.vocabItemId, "a")  // kept
    await model.retryButtonTapped()
    expectNoDifference(model.submitFailed, false)
    expectNoDifference(model.current?.vocabItemId, "b")  // advanced
  }

  @Test func gradedResultMergedIntoSharedVocabItems() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let updated = VocabItem(
      id: "a", targetLanguageCode: "es", sourceText: "s", targetText: "t",
      receptiveFamiliarity: 5)
    let model = withDependencies {
      $0.api.submitReview = { _, _, _ in updated }
    } operation: {
      ReviewSessionModel(cards: [card("a")])
    }
    await model.gotItButtonTapped()
    expectNoDifference(vocabItems.items[id: "a"]?.receptive.familiarity, 5)
  }

  @Test func typedFlowSubmitsOnlyOnContinue() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let submits = LockIsolated(0)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in
        submits.withValue { $0 += 1 }
        return stubItem(id)
      }
    } operation: {
      ReviewSessionModel(cards: [card("a", .productive)])
    }
    model.typedAnswer = "t-a"
    model.checkButtonTapped()
    expectNoDifference(model.typedGrade, .correct)
    expectNoDifference(submits.value, 0)  // nothing submitted at check time
    await model.continueButtonTapped()
    expectNoDifference(submits.value, 1)
  }
}
