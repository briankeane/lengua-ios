import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct SharedStateIsolationTraitTests {
  /// Directly exercises the trait: entering its scope must swap
  /// `defaultInMemoryStorage` for a brand-new, empty store, so a `@Shared` key
  /// mutated in the *outer* store resolves to its default inside the scope
  /// instead of leaking across. This is the exact guarantee that lets parallel
  /// suites stop racing. Deterministic and order-independent — it does not rely
  /// on test execution order or on how long a store retains released values.
  @Test func provideScopeInstallsFreshInMemoryStorage() async throws {
    let test = try #require(Test.current)

    let outerStore = InMemoryStorage()
    try await withDependencies {
      $0.defaultInMemoryStorage = outerStore
    } operation: {
      @Shared(.vocabItems) var outer = VocabItems()
      $outer.withLock { $0.isLoading = true }
      expectNoDifference(outer.isLoading, true)

      let sawLoading = LockIsolated(true)
      try await SharedStateIsolationTrait().provideScope(for: test, testCase: nil) {
        @Shared(.vocabItems) var scoped = VocabItems()
        sawLoading.setValue(scoped.isLoading)
      }
      // Inside the scope the fresh store has no value yet, so the key falls back
      // to its default (`isLoading == false`) — the outer mutation is invisible.
      expectNoDifference(sawLoading.value, false)

      // The outer store is untouched by the scoped work.
      expectNoDifference(outer.isLoading, true)
    }
  }

  /// The property the trait leans on: distinct `InMemoryStorage` instances never
  /// share state. A `@Shared` resolved against one store cannot observe a
  /// mutation made against another. Fresh-store-per-test is exactly what
  /// `.isolatedSharedState` provides.
  @Test func distinctInMemoryStoragesDoNotShareState() {
    let storageA = InMemoryStorage()
    let storageB = InMemoryStorage()

    withDependencies {
      $0.defaultInMemoryStorage = storageA
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems()
      $vocabItems.withLock { $0.isLoading = true }
      expectNoDifference(vocabItems.isLoading, true)
    }

    withDependencies {
      $0.defaultInMemoryStorage = storageB
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems()
      expectNoDifference(vocabItems.isLoading, false)  // storageB was never mutated
    }
  }
}
