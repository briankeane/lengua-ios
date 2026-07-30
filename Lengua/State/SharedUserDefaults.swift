import Foundation
import Sharing

extension SharedKey where Self == FileStorageKey<Auth>.Default {
  static var auth: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "auth.json")), default: Auth()]
  }
}

extension SharedKey where Self == InMemoryKey<MainContainerModel.ActiveTab>.Default {
  static var activeTab: Self {
    Self[.inMemory("activeTab"), default: .home]
  }
}

extension SharedKey where Self == InMemoryKey<MainContainerNavigationCoordinator>.Default {
  static var mainContainerNavigationCoordinator: Self {
    Self[.inMemory("mainContainerNavigationCoordinator"), default: MainContainerNavigationCoordinator()]
  }
}

extension SharedKey where Self == InMemoryKey<AppVersionRequirements?>.Default {
  static var appVersionRequirements: Self {
    Self[.inMemory("appVersionRequirements"), default: nil]
  }
}
