import Foundation

struct VocabItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
  let familiarity: Int
  let lastSeenAt: Date?
  let timesSeen: Int
  let timesCorrect: Int
  let timesIncorrect: Int
  let lastOutcome: String?
  let nextDueAt: Date?
  let createdAt: Date
  let updatedAt: Date
}
