import SwiftUI

@main
struct LenguaApp: App {
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
