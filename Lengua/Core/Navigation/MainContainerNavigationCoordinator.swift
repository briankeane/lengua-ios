import Foundation

@MainActor
@Observable
final class MainContainerNavigationCoordinator {
  enum Path: Hashable {
    case profile
  }

  var path: [Path] = []

  init(path: [Path] = []) {
    self.path = path
  }

  func push(_ item: Path) { path.append(item) }
  func pop() { _ = path.popLast() }
  func popToRoot() { path.removeAll() }
}
