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

  func directionEyebrow(_ direction: ReviewDirection) -> String {
    switch direction {
    case .receptive: return "Recognize"
    case .productive: return "Produce"
    }
  }

  var revealHint: String { "Tap to Reveal" }
  var missedItTitle: String { "Missed It" }
  var gotItTitle: String { "Got It" }

  var typedAnswerPlaceholder: String { "Type the answer" }
  var checkTitle: String { "Check" }
  var continueTitle: String { "Continue" }
  var overrideTitle: String { "I Was Right" }

  func resultTitle(for grade: TypedGrade) -> String {
    switch grade {
    case .correct, .correctWithAccentNote: return "Correct!"
    case .incorrect: return "Not Quite"
    }
  }

  func accentNote(for grade: TypedGrade) -> String? {
    guard grade == .correctWithAccentNote else { return nil }
    return "Close — watch the accent marks."
  }

  var retryButtonTitle: String { "Try Again" }
  var submitFailedText: String { "Couldn't save that." }

  var typedResultIsError: Bool { typedGrade == .incorrect }
  var showsCorrectOverride: Bool { typedGrade == .incorrect }

  var doneTitle: String { "Done" }
  var finishedText: String {
    "Session complete! You cleared \(clearedCount) of \(batchCount) cards."
  }

  // MARK: - Private Helpers
  private func grade(_ outcome: ReviewOutcome) async {
    guard let card = current, !isSubmittingGrade, !isClosed else { return }
    isSubmittingGrade = true
    submitFailed = false
    pendingOutcome = outcome
    do {
      let updated = try await api.submitReview(card.vocabItemId, card.direction, outcome)
      isSubmittingGrade = false
      guard !isClosed else { return }
      $vocabItems.withLock { $0.items[id: updated.id] = updated }
      applyOutcome(outcome, for: card)
      resetCardState()
    } catch {
      isSubmittingGrade = false
      guard !isClosed else { return }
      submitFailed = true
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

struct ReviewSessionView: View {
  @State var model: ReviewSessionModel
  let onDone: () -> Void

  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let cardColor = Color(red: 0.98, green: 0.98, blue: 0.96)

  var body: some View {
    ZStack {
      pageBlue.ignoresSafeArea()

      VStack(spacing: 24) {
        header
        Spacer()
        if model.isFinished {
          finishedCard
        } else if model.submitFailed {
          retryCard
        } else if let current = model.current {
          switch current.direction {
          case .receptive: flipCard(current)
          case .productive: typeCard(current)
          }
        }
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        ProgressView(value: model.progress)
          .tint(.white)
        Text(model.progressText)
          .font(.caption).fontWeight(.semibold)
          .foregroundStyle(.white.opacity(0.85))
      }
      Button {
        model.closeButtonTapped()
        onDone()
      } label: {
        Image(systemName: "xmark")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(width: 36, height: 36)
          .background(Circle().fill(.white.opacity(0.15)))
      }
    }
  }

  private func flipCard(_ current: ReviewCard) -> some View {
    VStack(spacing: 20) {
      Text(model.directionEyebrow(current.direction))
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.white.opacity(0.7))

      VStack(spacing: 16) {
        Text(current.targetText)
          .font(.largeTitle).fontWeight(.bold)
          .foregroundStyle(deepBlue)
          .multilineTextAlignment(.center)
        if model.isRevealed {
          Text(current.sourceText)
            .font(.title3)
            .foregroundStyle(deepBlue.opacity(0.7))
            .multilineTextAlignment(.center)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 20).fill(cardColor))

      if model.isRevealed {
        HStack(spacing: 16) {
          secondaryButton(model.missedItTitle) { Task { await model.missedItButtonTapped() } }
          primaryButton(model.gotItTitle) { Task { await model.gotItButtonTapped() } }
        }
        .disabled(model.isSubmittingGrade)
      } else {
        primaryButton(model.revealHint) { model.revealButtonTapped() }
      }
    }
  }

  private func typeCard(_ current: ReviewCard) -> some View {
    VStack(spacing: 20) {
      Text(model.directionEyebrow(current.direction))
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.white.opacity(0.7))

      VStack(spacing: 16) {
        Text(current.sourceText)
          .font(.largeTitle).fontWeight(.bold)
          .foregroundStyle(deepBlue)
          .multilineTextAlignment(.center)
        if let typedGrade = model.typedGrade {
          resultView(for: typedGrade, current: current)
        } else {
          TextField(model.typedAnswerPlaceholder, text: $model.typedAnswer)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.title2)
            .multilineTextAlignment(.center)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 20).fill(cardColor))

      if model.typedGrade != nil {
        if model.showsCorrectOverride {
          HStack(spacing: 16) {
            secondaryButton(model.overrideTitle) { model.markCorrectOverrideButtonTapped() }
            primaryButton(model.continueTitle) { Task { await model.continueButtonTapped() } }
          }
          .disabled(model.isSubmittingGrade)
        } else {
          primaryButton(model.continueTitle) { Task { await model.continueButtonTapped() } }
            .disabled(model.isSubmittingGrade)
        }
      } else {
        primaryButton(model.checkTitle) { model.checkButtonTapped() }
      }
    }
  }

  private func resultView(for grade: TypedGrade, current: ReviewCard) -> some View {
    VStack(spacing: 8) {
      Text(model.resultTitle(for: grade))
        .font(.title3).fontWeight(.bold)
        .foregroundStyle(model.typedResultIsError ? .red : deepBlue)
      Text(current.targetText)
        .font(.title2).fontWeight(.semibold)
        .foregroundStyle(deepBlue)
      if let accentNote = model.accentNote(for: grade) {
        Text(accentNote)
          .font(.subheadline)
          .foregroundStyle(deepBlue.opacity(0.7))
      }
    }
  }

  private var retryCard: some View {
    VStack(spacing: 16) {
      Text(model.submitFailedText)
        .font(.body)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      primaryButton(model.retryButtonTitle) { Task { await model.retryButtonTapped() } }
    }
  }

  private var finishedCard: some View {
    VStack(spacing: 20) {
      Text(model.finishedText)
        .font(.title2).fontWeight(.bold)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      primaryButton(model.doneTitle) { onDone() }
    }
  }

  private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .foregroundStyle(deepBlue)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Capsule().fill(.white))
    }
  }

  private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Capsule().stroke(.white, lineWidth: 2))
    }
  }
}
