import CustomDump
import Dependencies
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
}
