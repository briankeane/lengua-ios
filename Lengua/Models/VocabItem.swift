import Foundation

/// The request body for `POST /v1/vocab-items`. Only these three fields are ever
/// sent; the server owns `id`, `userId`, normalization, and all stats fields.
struct SaveVocabItemRequest: Encodable, Equatable, Sendable {
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
}

/// A saved vocabulary item as returned by `POST /v1/vocab-items` (200 or 201).
/// Only the fields the client uses are decoded; server-owned stats fields
/// (`familiarity`, `timesSeen`, …) are intentionally ignored.
struct VocabItem: Decodable, Equatable, Sendable {
  let id: String
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
}
