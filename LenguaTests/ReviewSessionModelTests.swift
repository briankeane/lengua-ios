import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized, .isolatedSharedState) struct ReviewSessionModelTests {
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

  @Test func missedCardReappearsAfterThreeOthers() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b"), card("c"), card("d"), card("e")])
    }
    await model.missedItButtonTapped()  // a missed -> reinserted at min(3, 4) = index 3
    expectNoDifference(model.current?.vocabItemId, "b")
    await model.gotItButtonTapped()  // b
    expectNoDifference(model.current?.vocabItemId, "c")
    await model.gotItButtonTapped()  // c
    expectNoDifference(model.current?.vocabItemId, "d")
    await model.gotItButtonTapped()  // d
    expectNoDifference(model.current?.vocabItemId, "a")  // a reappears after b, c, d
    await model.gotItButtonTapped()  // a, now correct
    expectNoDifference(model.current?.vocabItemId, "e")
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

  @Test func submitFailureKeepsCardAndRetryResendsSameOutcome() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let attempts = LockIsolated(0)
    let outcomes = LockIsolated<[ReviewOutcome]>([])
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, outcome in
        attempts.withValue { $0 += 1 }
        outcomes.withValue { $0.append(outcome) }
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
    expectNoDifference(model.clearedCount, 1)  // proves .correct was resent, not .incorrect
    expectNoDifference(outcomes.value, [.correct, .correct])
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

  @Test func typedIncorrectCanBeOverriddenToCorrect() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let outcomes = LockIsolated<[ReviewOutcome]>([])
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, outcome in
        outcomes.withValue { $0.append(outcome) }
        return stubItem(id)
      }
    } operation: {
      ReviewSessionModel(cards: [card("a", .productive)])
    }
    model.typedAnswer = "nope"
    model.checkButtonTapped()
    expectNoDifference(model.typedGrade, .incorrect)
    expectNoDifference(outcomes.value.isEmpty, true)  // nothing submitted yet

    model.markCorrectOverrideButtonTapped()
    await model.continueButtonTapped()

    expectNoDifference(outcomes.value, [.correct])
    expectNoDifference(model.clearedCount, 1)
  }

  @Test func closedSessionIgnoresLateResponse() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in
        started.continuation.yield()
        var iterator = release.stream.makeAsyncIterator()
        _ = await iterator.next()  // suspend until the test releases it, after closing
        return stubItem(id)
      }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b")])
    }

    async let grading: Void = model.gotItButtonTapped()
    var startedIterator = started.stream.makeAsyncIterator()
    _ = await startedIterator.next()  // wait until the submit is genuinely in flight

    model.closeButtonTapped()
    release.continuation.yield()  // let the in-flight submit resolve after closing
    await grading

    expectNoDifference(vocabItems.items.isEmpty, true)  // late response never merged
    expectNoDifference(model.resolvedCount, 0)
    expectNoDifference(model.clearedCount, 0)
    expectNoDifference(model.current?.vocabItemId, "a")  // card never removed
    expectNoDifference(model.isSubmittingGrade, false)  // flag not stranded true
  }

  @Test func doubleSubmitWhileInFlightOnlySubmitsOnce() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let submitCount = LockIsolated(0)
    let started = AsyncStream.makeStream(of: Void.self)
    let release = AsyncStream.makeStream(of: Void.self)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in
        submitCount.withValue { $0 += 1 }
        started.continuation.yield()
        var iterator = release.stream.makeAsyncIterator()
        _ = await iterator.next()
        return stubItem(id)
      }
    } operation: {
      ReviewSessionModel(cards: [card("a")])
    }

    async let first: Void = model.gotItButtonTapped()
    var startedIterator = started.stream.makeAsyncIterator()
    _ = await startedIterator.next()  // wait until the first submit is genuinely in flight

    await model.gotItButtonTapped()  // in-flight guard should no-op, not submit again
    expectNoDifference(submitCount.value, 1)

    release.continuation.yield()
    await first
    expectNoDifference(model.clearedCount, 1)
  }

  @Test func progressReflectsResolvedOfBatch() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: {
      ReviewSessionModel(cards: [card("a"), card("b"), card("c")])
    }
    await model.gotItButtonTapped()
    expectNoDifference(model.progressText, "1 of 3")
    expectNoDifference(model.progress, 1.0 / 3.0)
  }

  @Test func batchCountCountsEntriesNotDistinctVocabItems() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewSessionModel(cards: [card("a", .receptive), card("a", .productive)])
    expectNoDifference(model.batchCount, 2)
  }

  @Test func stringHelpersProvideExpectedTitles() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewSessionModel(cards: [card("a")])
    expectNoDifference(model.gotItTitle, "Got It")
    expectNoDifference(model.missedItTitle, "Missed It")
    expectNoDifference(model.doneTitle, "Done")
    expectNoDifference(model.directionEyebrow(.receptive), "Recognize")
    expectNoDifference(model.directionEyebrow(.productive), "Produce")
  }

  @Test func typedResultBooleansReflectWrongVsRightAnswer() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewSessionModel(cards: [card("a", .productive)])

    model.typedAnswer = "nope"
    model.checkButtonTapped()
    expectNoDifference(model.typedResultIsError, true)
    expectNoDifference(model.showsCorrectOverride, true)

    model.typedAnswer = "t-a"
    model.checkButtonTapped()
    expectNoDifference(model.typedResultIsError, false)
    expectNoDifference(model.showsCorrectOverride, false)
  }

  @Test func resultTitleAndAccentNoteDistinguishCorrectFromAccentedCorrect() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewSessionModel(cards: [card("a", .productive)])
    expectNoDifference(model.resultTitle(for: .correct), "Correct!")
    expectNoDifference(model.resultTitle(for: .correctWithAccentNote), "Correct!")
    expectNoDifference(model.resultTitle(for: .incorrect), "Not Quite")
    expectNoDifference(model.accentNote(for: .correct), nil)
    expectNoDifference(
      model.accentNote(for: .correctWithAccentNote), "Close — watch the accent marks.")
    expectNoDifference(model.accentNote(for: .incorrect), nil)
  }
}
