import CustomDump
import Testing

@testable import Lengua

@MainActor
struct MainContainerNavigationCoordinatorTests {
  @Test func pushAppendsToPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    expectNoDifference(coordinator.path, [.profile])
  }

  @Test func popRemovesLast() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.pop()
    expectNoDifference(coordinator.path, [])
  }

  @Test func popToRootClearsPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.push(.profile)
    coordinator.popToRoot()
    expectNoDifference(coordinator.path, [])
  }
}
