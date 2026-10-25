import Foundation

/// The request body for `POST /v1/vocab-items`. Only these three fields are ever
/// sent; the server owns `id`, `userId`, normalization, and all stats fields.
struct SaveVocabItemRequest: Encodable, Equatable, Sendable {
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
}

/// Per-direction spaced-repetition stats for a `VocabItem`. A vocab item tracks
/// receptive (recognize the target text) and productive (produce the target
/// text) proficiency independently.
struct SRSTrack: Codable, Equatable, Sendable {
  let familiarity: Int
  let nextDueAt: Date?
  let lastSeenAt: Date?
  let timesSeen: Int
  let timesCorrect: Int
  let timesIncorrect: Int
  let lastOutcome: String?
}

/// A vocabulary item as returned by the server (the `GET /v1/vocab-items` list
/// and the `POST /v1/vocab-items` save both return this full shape). Decode with
/// `JSONDecoder.lenguaISO8601` for the fractional-second timestamps.
struct VocabItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
  let receptive: SRSTrack
  let productive: SRSTrack
  let createdAt: Date
  let updatedAt: Date
}
