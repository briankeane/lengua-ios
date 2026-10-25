import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
struct VocabItemTests {
  private func decode(_ json: String) throws -> VocabItem {
    try JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: Data(json.utf8))
  }

  @Test func decodesFullPayloadWithFractionalSeconds() throws {
    let item = try decode(
      """
      {
        "id": "b1c3f9e2", "targetLanguageCode": "es",
        "sourceText": "dog", "targetText": "perro",
        "receptive": { "familiarity": 3, "lastSeenAt": "2026-08-01T10:00:00.500Z",
          "timesSeen": 4, "timesCorrect": 3, "timesIncorrect": 1, "lastOutcome": "correct",
          "nextDueAt": "2026-08-02T10:00:00.000Z" },
        "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "createdAt": "2026-08-01T10:00:00.000Z",
        "updatedAt": "2026-08-01T10:00:00.000Z"
      }
      """)
    expectNoDifference(item.id, "b1c3f9e2")
    expectNoDifference(item.targetText, "perro")
    expectNoDifference(item.sourceText, "dog")
    expectNoDifference(item.receptive.familiarity, 3)
    expectNoDifference(item.receptive.lastOutcome, "correct")
    expectNoDifference(item.receptive.timesSeen, 4)
    expectNoDifference(item.createdAt, Date(timeIntervalSince1970: 1_785_578_400))
  }

  @Test func decodesNullOptionalsAndZeroCounts() throws {
    let item = try decode(
      """
      {
        "id": "x1", "targetLanguageCode": "es",
        "sourceText": "cat", "targetText": "gato",
        "receptive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "createdAt": "2026-08-01T10:00:00.000Z",
        "updatedAt": "2026-08-01T10:00:00.000Z"
      }
      """)
    expectNoDifference(item.receptive.lastSeenAt, nil)
    expectNoDifference(item.receptive.nextDueAt, nil)
    expectNoDifference(item.receptive.lastOutcome, nil)
    expectNoDifference(item.receptive.familiarity, 0)
  }

  @Test func decodesTimestampWithoutFractionalSeconds() throws {
    let item = try decode(
      """
      {
        "id": "x2", "targetLanguageCode": "es",
        "sourceText": "cat", "targetText": "gato",
        "receptive": { "familiarity": 1, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "createdAt": "2026-08-01T10:00:00Z", "updatedAt": "2026-08-01T10:00:00Z"
      }
      """)
    expectNoDifference(item.createdAt, Date(timeIntervalSince1970: 1_785_578_400))
  }

  @Test func throwsOnUnparseableDate() {
    #expect(throws: DecodingError.self) {
      try decode(
        """
        {
          "id": "x3", "targetLanguageCode": "es",
          "sourceText": "cat", "targetText": "gato",
          "receptive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
            "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
          "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
            "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
          "createdAt": "not-a-date", "updatedAt": "not-a-date"
        }
        """)
    }
  }
}
