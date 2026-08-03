import Dependencies
import DependenciesMacros
import IdentifiedCollections
import Sharing

@DependencyClient
struct VocabItemsClient: Sendable {
  /// Loads every page of the caller's vocab items into `@Shared(.vocabItems)`.
  /// Coalesced: a call while a load is already running is a no-op.
  var refresh: @Sendable () async -> Void
  /// Resets `@Shared(.vocabItems)` to empty (used on sign-out).
  var clear: @Sendable () -> Void
  /// Deletes one vocab item server-side, then removes it from
  /// `@Shared(.vocabItems)` on success. Throws on failure without mutating
  /// shared state. Bound to the current account: a sign-out or account switch
  /// mid-delete discards the local removal.
  var delete: @Sendable (_ id: String) async throws -> Void
}

extension VocabItemsClient: DependencyKey {
  static let liveValue = VocabItemsClient(
    refresh: {
      @Shared(.vocabItems) var vocabItems
      @Shared(.auth) var auth
      let startingToken = auth.jwtToken  // bind this load to the current account
      let shouldStart = $vocabItems.withLock { state -> Bool in
        guard !state.isLoading else { return false }
        state.isLoading = true
        state.loadFailed = false
        return true
      }
      guard shouldStart else { return }

      @Dependency(\.api) var api
      do {
        var loaded: [VocabItem] = []
        var cursor: String?
        repeat {
          let page = try await api.getVocabItems(nil, 100, cursor)
          loaded.append(contentsOf: page.items)
          cursor = page.nextCursor
        } while cursor != nil

        $vocabItems.withLock { state in
          // Only commit if the same account that started the load is still
          // signed in: a sign-out or account switch mid-load must not
          // repopulate the shared Library with the previous user's items.
          if auth.jwtToken == startingToken {
            // De-dupe rather than trap: keyset pagination can repeat an id
            // across page boundaries if rows shift mid-fetch. Keep the first.
            state.items = IdentifiedArray(loaded, id: \.id) { first, _ in first }
          }
          state.isLoading = false
        }
      } catch is CancellationError {
        $vocabItems.withLock { $0.isLoading = false }
      } catch {
        $vocabItems.withLock { state in
          state.isLoading = false
          state.loadFailed = true
        }
      }
    },
    clear: {
      @Shared(.vocabItems) var vocabItems
      $vocabItems.withLock { $0 = VocabItems() }
    },
    delete: { id in
      @Shared(.auth) var auth
      let startingToken = auth.jwtToken  // bind this delete to the current account

      @Dependency(\.api) var api
      try await api.deleteVocabItem(id)

      @Shared(.vocabItems) var vocabItems
      $vocabItems.withLock { state in
        // Only mutate if the same account that started the delete is still
        // signed in: an account switch mid-delete must not touch the new
        // account's library.
        if auth.jwtToken == startingToken {
          _ = state.items.remove(id: id)
        }
      }
    }
  )
}

extension DependencyValues {
  var vocabItemsClient: VocabItemsClient {
    get { self[VocabItemsClient.self] }
    set { self[VocabItemsClient.self] = newValue }
  }
}
