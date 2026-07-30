import Foundation

enum DevelopmentEnvironment: String {
  case local, development, staging, production
}

final class Config: Sendable {
  static let shared = Config()

  let environment: DevelopmentEnvironment
  let sentryDSN: String?

  var baseUrl: URL {
    switch environment {
    case .local:
      return URL(string: "http://localhost:10020")!
    case .development, .staging, .production:
      // TODO: point staging/production at real hosts when they exist.
      return URL(string: "http://localhost:10020")!
    }
  }

  private init() {
    let rawEnv = Config.optional("DEV_ENVIRONMENT") ?? "development"
    self.environment = DevelopmentEnvironment(rawValue: rawEnv) ?? .development
    self.sentryDSN = Config.optional("SENTRY_DSN")
  }

  /// Returns nil when the Info.plist value is missing, empty, or an unresolved
  /// `$(...)` build-setting placeholder.
  static func optional(_ name: String) -> String? {
    guard let value = Bundle.main.infoDictionary?[name] as? String else { return nil }
    if value.isEmpty || value.hasPrefix("$(") { return nil }
    return value
  }
}
