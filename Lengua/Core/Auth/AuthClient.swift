import Dependencies
import DependenciesMacros
import Sharing

@DependencyClient
struct AuthClient: Sendable {
  var signOut: @Sendable () async -> Void
}

extension AuthClient: DependencyKey {
  static let liveValue = AuthClient(
    signOut: {
      @Shared(.auth) var auth
      $auth.withLock { $0 = Auth() }
    }
  )
  static let testValue = AuthClient(signOut: {})
}

extension DependencyValues {
  var authClient: AuthClient {
    get { self[AuthClient.self] }
    set { self[AuthClient.self] = newValue }
  }
}
