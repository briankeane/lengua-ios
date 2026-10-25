import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
@Suite struct ReviewAPIDecodingTests {
  @Test func decodesReviewQueueEnvelope() throws {
    let json = Data(
      """
      { "reviewCards": [
          { "vocabItemId": "v1", "direction": "receptive", "sourceText": "the dog",
            "targetText": "el perro", "targetLanguageCode": "es", "familiarity": 0, "nextDueAt": null } ],
        "dueCounts": { "receptive": 12, "productive": 3, "total": 15 } }
      """.utf8)
    let decoded = try JSONDecoder.lenguaISO8601.decode(ReviewQueueResponse.self, from: json)
    expectNoDifference(decoded.reviewCards.first?.id, "v1#receptive")
    expectNoDifference(decoded.dueCounts, DueCounts(receptive: 12, productive: 3, total: 15))
  }
}
