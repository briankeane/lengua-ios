import Dependencies
import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    ErrorReporting.start()
    return true
  }
}

@main
struct LenguaApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    Task {
      @Dependency(\.analytics) var analytics
      await analytics.initialize()
    }
  }

  var body: some Scene {
    WindowGroup {
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        EmptyView()
      } else {
        ContentView()
      }
    }
  }
}
