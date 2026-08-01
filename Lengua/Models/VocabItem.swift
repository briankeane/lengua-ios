import Foundation

/// The request body for `POST /v1/vocab-items`. Only these three fields are ever
/// sent; the server owns `id`, `userId`, normalization, and all stats fields.
struct SaveVocabItemRequest: Encodable, Equatable, Sendable {
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
}

/// A vocabulary item as returned by the server (the `GET /v1/vocab-items` list
/// and the `POST /v1/vocab-items` save both return this full shape). Decode with
/// `JSONDecoder.lenguaISO8601` for the fractional-second timestamps.
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
