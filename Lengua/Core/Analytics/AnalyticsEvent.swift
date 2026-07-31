enum AnalyticsEvent: Equatable {
  case signInStarted(method: AuthMethod)
  case signInCompleted(method: AuthMethod, userId: String)
  case signInFailed(method: AuthMethod, error: String)
}

enum AuthMethod: String {
  case apple
  case google
}
