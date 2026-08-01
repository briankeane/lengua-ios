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

  @Test func appleSignInResponseDecodesUserAndToken() throws {
    let json = Data(
      """
      {
        "user": {
          "id": "apple-u1",
          "firstName": "Sam",
          "lastName": "Lee",
          "displayName": "Sam Lee",
          "email": "sam@example.com",
          "profileImageUrl": "https://img/1.png",
          "role": "user"
        },
        "token": "jwt-apple-123"
      }
      """.utf8)

    let decoded = try JSONDecoder().decode(AppleSignInResponse.self, from: json)

    expectNoDifference(decoded.token, "jwt-apple-123")
    expectNoDifference(decoded.result.user.id, "apple-u1")
    expectNoDifference(decoded.result.user.email, "sam@example.com")
    expectNoDifference(decoded.result.user.firstName, "Sam")
    expectNoDifference(decoded.result.token, "jwt-apple-123")
  }

  @Test func vocabItemDecodesIgnoringServerOwnedFields() throws {
    let json = Data(
      """
      {
        "id": "item-1",
        "userId": "user-1",
        "targetLanguageCode": "es",
        "sourceText": "the dog",
        "targetText": "el perro",
        "targetTextNormalized": "el perro",
        "familiarity": 0,
        "lastSeenAt": null,
        "timesSeen": 0,
        "timesCorrect": 0,
        "timesIncorrect": 0,
        "lastOutcome": null,
        "nextDueAt": null,
        "createdAt": "2026-08-01T00:00:00.000Z",
        "updatedAt": "2026-08-01T00:00:00.000Z"
      }
      """.utf8)

    let decoded = try JSONDecoder().decode(VocabItem.self, from: json)

    expectNoDifference(decoded.id, "item-1")
    expectNoDifference(decoded.targetLanguageCode, "es")
    expectNoDifference(decoded.sourceText, "the dog")
    expectNoDifference(decoded.targetText, "el perro")
  }
}
