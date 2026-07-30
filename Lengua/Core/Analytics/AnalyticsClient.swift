import Dependencies
import DependenciesMacros

@DependencyClient
struct AnalyticsClient: Sendable {
  var initialize: @Sendable () async -> Void
}

extension AnalyticsClient: DependencyKey {
  // No-op until a real analytics provider (e.g. Mixpanel) is added.
  static let liveValue = AnalyticsClient(initialize: {})
  static let testValue = AnalyticsClient(initialize: {})
}

extension DependencyValues {
  var analytics: AnalyticsClient {
    get { self[AnalyticsClient.self] }
    set { self[AnalyticsClient.self] = newValue }
  }
}
