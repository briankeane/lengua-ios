import Dependencies
import XCTest

@testable import Lengua

@MainActor
final class APIClientTests: XCTestCase {
  func testGetAppVersionRequirementsUsesInjectedDependency() async throws {
    let result = try await withDependencies {
      $0.api.getAppVersionRequirements = { AppVersionRequirements(minimumVersion: "1.2.3") }
    } operation: {
      @Dependency(\.api) var api
      return try await api.getAppVersionRequirements()
    }
    XCTAssertEqual(result.minimumVersion, "1.2.3")
  }
}
