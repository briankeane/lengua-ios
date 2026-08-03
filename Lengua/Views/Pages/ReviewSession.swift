import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ReviewSessionModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  init(cards: [ReviewCard]) {
    self.queue = cards
    self.batchCount = cards.count
    super.init()
  }

  // MARK: - Properties
  private var queue: [ReviewCard]
  private var missCounts: [String: Int] = [:]
  private var isClosed = false
  private var pendingOutcome: ReviewOutcome?
  private var pendingTypedOutcome: ReviewOutcome?

  let batchCount: Int
  private(set) var clearedCount = 0
  private(set) var resolvedCount = 0
  private(set) var isFinished = false
  var isSubmittingGrade = false
  private(set) var submitFailed = false

  var isRevealed = false
  var typedAnswer = ""
  private(set) var typedGrade: TypedGrade?

  // MARK: - User Actions
  func revealButtonTapped() { isRevealed = true }
  func gotItButtonTapped() async { await grade(.correct) }
  func missedItButtonTapped() async { await grade(.incorrect) }

  func checkButtonTapped() {
    guard let card = current else { return }
    let grade = gradeTypedAnswer(typedAnswer, expected: card.targetText)
    typedGrade = grade
    pendingTypedOutcome = grade == .incorrect ? .incorrect : .correct
  }
  func markCorrectOverrideButtonTapped() {
    typedGrade = .correct
    pendingTypedOutcome = .correct
  }
  func continueButtonTapped() async {
    guard let outcome = pendingTypedOutcome else { return }
    await grade(outcome)
  }
  func retryButtonTapped() async {
    guard let outcome = pendingOutcome else { return }
    await grade(outcome)
  }
  func closeButtonTapped() { isClosed = true }

  // MARK: - View Helpers
  var current: ReviewCard? { queue.first }
  var progress: Double { batchCount == 0 ? 0 : Double(resolvedCount) / Double(batchCount) }
  var progressText: String { "\(resolvedCount) of \(batchCount)" }

  // MARK: - Private Helpers
  private func grade(_ outcome: ReviewOutcome) async {
    guard let card = current, !isSubmittingGrade else { return }
    isSubmittingGrade = true
    submitFailed = false
    pendingOutcome = outcome
    do {
      let updated = try await api.submitReview(card.vocabItemId, card.direction, outcome)
      guard !isClosed else { return }
      $vocabItems.withLock { $0.items[id: updated.id] = updated }
      applyOutcome(outcome, for: card)
      resetCardState()
      isSubmittingGrade = false
    } catch {
      guard !isClosed else { return }
      submitFailed = true
      isSubmittingGrade = false
    }
  }

  private func applyOutcome(_ outcome: ReviewOutcome, for card: ReviewCard) {
    queue.removeFirst()
    switch outcome {
    case .correct:
      clearedCount += 1
      resolvedCount += 1
    case .incorrect:
      let misses = (missCounts[card.id] ?? 0) + 1
      missCounts[card.id] = misses
      if misses < 3 {
        queue.insert(card, at: min(3, queue.count))
      } else {
        resolvedCount += 1  // dropped for good
      }
    }
    if queue.isEmpty { isFinished = true }
  }

  private func resetCardState() {
    isRevealed = false
    typedAnswer = ""
    typedGrade = nil
    pendingTypedOutcome = nil
    pendingOutcome = nil
  }
}
