import Dependencies
import DependenciesMacros

@DependencyClient
struct AnalyticsClient: Sendable {
  var initialize: @Sendable () async -> Void
  var track: @Sendable (_ event: AnalyticsEvent) async -> Void
}

extension AnalyticsClient: DependencyKey {
  // No-op until a real analytics provider (e.g. Mixpanel) is added.
  static let liveValue = AnalyticsClient(initialize: {}, track: { _ in })
  static let testValue = AnalyticsClient(initialize: {}, track: { _ in })
}

extension DependencyValues {
  var analytics: AnalyticsClient {
    get { self[AnalyticsClient.self] }
    set { self[AnalyticsClient.self] = newValue }
  }
}
