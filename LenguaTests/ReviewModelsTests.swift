import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
@Suite struct ReviewModelsTests {
  @Test func decodesNestedVocabItemTracks() throws {
    let json = """
      { "id": "v1", "targetLanguageCode": "es", "sourceText": "the dog", "targetText": "el perro",
        "receptive":  { "familiarity": 2, "nextDueAt": null, "lastSeenAt": null,
          "timesSeen": 3, "timesCorrect": 2, "timesIncorrect": 1, "lastOutcome": "correct" },
        "productive": { "familiarity": 0, "nextDueAt": null, "lastSeenAt": null,
          "timesSeen": 0, "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null },
        "createdAt": "2026-08-01T00:00:00.000Z", "updatedAt": "2026-08-01T00:00:00.000Z" }
      """
    let item = try JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: Data(json.utf8))
    expectNoDifference(item.receptive.familiarity, 2)
    expectNoDifference(item.receptive.lastOutcome, "correct")
    expectNoDifference(item.productive.familiarity, 0)
  }

  @Test func reviewCardIdentityCombinesItemAndDirection() {
    let card = ReviewCard(
      vocabItemId: "v1", sourceText: "the dog", targetText: "el perro",
      targetLanguageCode: "es", direction: .receptive, familiarity: 0, nextDueAt: nil)
    expectNoDifference(card.id, "v1#receptive")
  }
}
