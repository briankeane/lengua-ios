import Foundation
import Sentry

enum ErrorReporting {
  static func start() {
    let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    guard !isRunningTests, let dsn = Config.shared.sentryDSN else { return }

    SentrySDK.start { options in
      options.dsn = dsn
      options.sendDefaultPii = false
      options.tracesSampleRate = 0.1
    }
  }
}
