import Foundation

struct Auth: Codable, Equatable, Sendable {
  var jwtToken: String?
  var currentUser: User?

  var isLoggedIn: Bool { jwtToken != nil }

  // NB: default is logged-out. This is persisted via @Shared(.auth) FileStorage.
  // TODO(auth): move token storage to Keychain before real sign-in ships;
  // do not persist real JWTs in app-container JSON.
  init(jwtToken: String? = nil, currentUser: User? = nil) {
    self.jwtToken = jwtToken
    self.currentUser = currentUser
  }
}
