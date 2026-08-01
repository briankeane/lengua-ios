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
}

extension VocabItemsClient: DependencyKey {
  static let liveValue = VocabItemsClient(
    refresh: {
      @Shared(.vocabItems) var vocabItems
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

        @Shared(.auth) var auth
        $vocabItems.withLock { state in
          if auth.isLoggedIn {  // a sign-out mid-load must not repopulate
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
    }
  )
}

extension DependencyValues {
  var vocabItemsClient: VocabItemsClient {
    get { self[VocabItemsClient.self] }
    set { self[VocabItemsClient.self] = newValue }
  }
}
