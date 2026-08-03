import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct APIClient: Sendable {
  /// Fetches minimum app version requirements (no auth required).
  var getAppVersionRequirements: @Sendable () async throws -> AppVersionRequirements = {
    AppVersionRequirements(minimumVersion: "0.0.0")
  }

  /// Simple server reachability check against the configured base URL.
  var health: @Sendable () async throws -> Bool = { true }

  /// Exchanges a Google ID token for a Lengua session (JWT + user).
  var signInViaGoogle: @Sendable (_ idToken: String) async throws -> GoogleSignInResult

  /// Fetches one page of the caller's vocab items (auth required).
  var getVocabItems:
    @Sendable (
      _ targetLanguageCode: String?,
      _ limit: Int?,
      _ cursor: String?
    ) async throws -> VocabItemsPage

  /// Saves a translated word/phrase for the signed-in user (auth required).
  /// The server treats 201 (newly saved) and 200 (already saved) identically,
  /// so both resolve to the returned item without error.
  var saveVocabItem: @Sendable (_ request: SaveVocabItemRequest) async throws -> VocabItem

  /// Permanently deletes one of the signed-in user's vocab items (auth required).
  /// The server returns 204 on delete and 404 when the item is already gone or
  /// owned by someone else; both mean "no longer exists", so both resolve without
  /// error.
  var deleteVocabItem: @Sendable (_ id: String) async throws -> Void

  /// Fetches the caller's due review cards (auth required). `direction == nil` ⇒ "any".
  var getReviewQueue:
    @Sendable (
      _ direction: ReviewDirection?, _ limit: Int?, _ targetLanguageCode: String?
    ) async throws -> ReviewQueue

  /// Records the outcome of reviewing one track of one card and returns the updated item.
  var submitReview:
    @Sendable (
      _ vocabItemId: String, _ direction: ReviewDirection, _ outcome: ReviewOutcome
    ) async throws -> VocabItem
}

struct GoogleSignInResult: Equatable, Sendable {
  let user: User
  let token: String
}

/// Decodes the `POST /v1/auth/google` response `{ user, token }`.
/// Extra server fields (`displayName`, `role`) are intentionally ignored.
struct GoogleSignInResponse: Decodable {
  struct APIUser: Decodable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
  }
  let user: APIUser
  let token: String

  var result: GoogleSignInResult {
    GoogleSignInResult(
      user: User(
        id: user.id, email: user.email, firstName: user.firstName,
        lastName: user.lastName, profileImageUrl: user.profileImageUrl),
      token: token)
  }
}

struct VocabItemsPage: Equatable, Sendable {
  var items: [VocabItem]
  var nextCursor: String?
}

/// Decodes the `GET /v1/vocab-items` response envelope.
struct VocabItemsResponse: Decodable {
  struct Pagination: Decodable {
    let limit: Int
    let nextCursor: String?
  }
  let vocabItems: [VocabItem]
  let pagination: Pagination
}

/// Decodes the `GET /v1/vocab-items/review` response envelope.
struct ReviewQueueResponse: Decodable {
  let reviewCards: [ReviewCard]
  let dueCounts: DueCounts
}

enum APIError: Error, LocalizedError {
  case dataNotValid
  case validationError(String)
  case unauthorized

  var errorDescription: String? {
    switch self {
    case .dataNotValid: return "Invalid data received from server"
    case .validationError(let message): return message
    case .unauthorized: return "You need to be signed in to do that"
    }
  }
}

extension DependencyValues {
  var api: APIClient {
    get { self[APIClient.self] }
    set { self[APIClient.self] = newValue }
  }
}

extension APIClient: TestDependencyKey {
  static let testValue = APIClient()
}
