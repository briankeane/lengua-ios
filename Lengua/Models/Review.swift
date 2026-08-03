import Foundation

/// Which skill a review card exercises: recognizing the target text
/// (receptive) or producing it (productive).
enum ReviewDirection: String, Codable, Sendable {
  case receptive
  case productive
}

/// The user's self-reported result for a reviewed card.
enum ReviewOutcome: String, Codable, Sendable {
  case correct
  case incorrect
}

/// A single flashcard due for review: one `VocabItem` in one `ReviewDirection`.
struct ReviewCard: Codable, Equatable, Sendable, Identifiable {
  let vocabItemId: String
  let sourceText: String
  let targetText: String
  let targetLanguageCode: String
  let direction: ReviewDirection
  let familiarity: Int
  let nextDueAt: Date?

  var id: String { "\(vocabItemId)#\(direction.rawValue)" }
}

/// The number of cards due per direction, plus the combined total.
struct DueCounts: Codable, Equatable, Sendable {
  let receptive: Int
  let productive: Int
  let total: Int
}

/// A batch of due review cards, along with the due counts they were drawn from.
struct ReviewQueue: Equatable, Sendable {
  let cards: [ReviewCard]
  let dueCounts: DueCounts
}
