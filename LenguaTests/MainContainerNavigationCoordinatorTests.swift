import XCTest

@testable import Lengua

@MainActor
final class MainContainerNavigationCoordinatorTests: XCTestCase {
  func testPushAppendsToPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    XCTAssertEqual(coordinator.path, [.profile])
  }

  func testPopRemovesLast() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.pop()
    XCTAssertEqual(coordinator.path, [])
  }

  func testPopToRootClearsPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.push(.profile)
    coordinator.popToRoot()
    XCTAssertEqual(coordinator.path, [])
  }
}
