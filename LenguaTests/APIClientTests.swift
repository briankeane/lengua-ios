import CustomDump
import Dependencies
import Foundation
import Testing

@testable import Lengua

@MainActor
struct APIClientTests {
  @Test func getAppVersionRequirementsUsesInjectedDependency() async throws {
    let result = try await withDependencies {
      $0.api.getAppVersionRequirements = { AppVersionRequirements(minimumVersion: "1.2.3") }
    } operation: {
      @Dependency(\.api) var api
      return try await api.getAppVersionRequirements()
    }
    expectNoDifference(result.minimumVersion, "1.2.3")
  }

  @Test func googleSignInResponseDecodesUserAndToken() throws {
    let json = Data(
      """
      {
        "user": {
          "id": "u1",
          "firstName": "Sam",
          "lastName": "Lee",
          "displayName": "Sam Lee",
          "email": "sam@example.com",
          "profileImageUrl": "https://img/1.png",
          "role": "user"
        },
        "token": "jwt-123"
      }
      """.utf8)

    let decoded = try JSONDecoder().decode(GoogleSignInResponse.self, from: json)

    expectNoDifference(decoded.token, "jwt-123")
    expectNoDifference(decoded.user.id, "u1")
    expectNoDifference(decoded.user.email, "sam@example.com")
    expectNoDifference(decoded.user.firstName, "Sam")
    expectNoDifference(decoded.user.profileImageUrl, "https://img/1.png")
  }

  @Test func getVocabItemsUsesInjectedDependency() async throws {
    let page = try await withDependencies {
      $0.api.getVocabItems = { languageCode, limit, cursor in
        expectNoDifference(languageCode, nil)
        expectNoDifference(limit, 100)
        expectNoDifference(cursor, nil)
        return VocabItemsPage(
          items: [
            VocabItem(
              id: "1", targetLanguageCode: "es", sourceText: "dog",
              targetText: "perro")
          ],
          nextCursor: "next-token")
      }
    } operation: {
      @Dependency(\.api) var api
      return try await api.getVocabItems(nil, 100, nil)
    }
    expectNoDifference(page.items.map(\.id), ["1"])
    expectNoDifference(page.nextCursor, "next-token")
  }

  @Test func vocabItemsResponseDecodesEnvelope() throws {
    let json = Data(
      """
      {
        "vocabItems": [
          { "id": "1", "targetLanguageCode": "es", "sourceText": "dog",
            "targetText": "perro",
            "receptive": { "familiarity": 2, "lastSeenAt": null, "timesSeen": 0,
              "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
            "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
              "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
            "createdAt": "2026-08-01T10:00:00.000Z",
            "updatedAt": "2026-08-01T10:00:00.000Z" }
        ],
        "pagination": { "limit": 50, "nextCursor": null }
      }
      """.utf8)
    let decoded = try JSONDecoder.lenguaISO8601.decode(VocabItemsResponse.self, from: json)
    expectNoDifference(decoded.vocabItems.map(\.targetText), ["perro"])
    expectNoDifference(decoded.pagination.nextCursor, nil)
  }

  @Test func vocabItemDecodesIgnoringUnknownServerFields() throws {
    let json = Data(
      """
      {
        "id": "item-1",
        "userId": "user-1",
        "targetLanguageCode": "es",
        "sourceText": "the dog",
        "targetText": "el perro",
        "targetTextNormalized": "el perro",
        "receptive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "productive": { "familiarity": 0, "lastSeenAt": null, "timesSeen": 0,
          "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null },
        "createdAt": "2026-08-01T00:00:00.000Z",
        "updatedAt": "2026-08-01T00:00:00.000Z"
      }
      """.utf8)

    let decoded = try JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: json)

    expectNoDifference(decoded.id, "item-1")
    expectNoDifference(decoded.targetLanguageCode, "es")
    expectNoDifference(decoded.sourceText, "the dog")
    expectNoDifference(decoded.targetText, "el perro")
  }
}
