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
}
