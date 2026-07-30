import Foundation

struct User: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let email: String
  var firstName: String?
  var lastName: String?
  var profileImageUrl: String?
}
