import Foundation
import IdentifiedCollections

/// App-wide vocab items plus their load status. In-memory shared state
/// (`@Shared(.vocabItems)`); the server is the source of truth.
struct VocabItems: Equatable, Sendable {
  var items: IdentifiedArrayOf<VocabItem> = []
  var isLoading = false
  var loadFailed = false
}
