import Dependencies
import Sharing
import Testing

/// A swift-testing trait that gives every test in a suite its own fresh backing
/// storage for process-global `@Shared` state.
///
/// swift-testing runs separate top-level `@Suite`s in parallel, and `.serialized`
/// only orders tests *within* one suite. The `@Shared(.inMemory(…))`,
/// `.fileStorage(…)`, and `.appStorage(…)` strategies all resolve their backing
/// store from process-wide `@Dependency` values (`defaultInMemoryStorage`,
/// `defaultFileStorage`, `defaultAppStorage`). In the live dependency context
/// those stores are shared across the whole process, so two suites touching the
/// same key (e.g. `@Shared(.vocabItems)` or `@Shared(.auth)`) stomp on each
/// other mid-assertion — an intermittent, run-varying failure.
///
/// Applying `.isolatedSharedState` to a suite scopes each of its tests in a
/// `withDependencies { … }` that swaps those three defaults for brand-new,
/// empty stores. Each test then reads and writes its own isolated state, so
/// parallel suites can no longer race. This uses only the core `Dependencies`
/// module — it deliberately does not pull in `DependenciesTestSupport`, which
/// would flip every test into the `.test` dependency context and break suites
/// that rely on live-context dependency inheritance.
struct SharedStateIsolationTrait: TestTrait, SuiteTrait, TestScoping {
  var isRecursive: Bool { true }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
    // Scope each individual test case, not the suite as a whole, so every test
    // gets its own fresh storage rather than sharing one store per suite.
    testCase == nil ? nil : self
  }

  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await withDependencies {
      $0.defaultInMemoryStorage = InMemoryStorage()
      $0.defaultFileStorage = .inMemory
      $0.defaultAppStorage = .inMemory
    } operation: {
      try await function()
    }
  }
}

extension Trait where Self == SharedStateIsolationTrait {
  /// Isolates process-global `@Shared` storage per test so parallel suites do
  /// not race on the same in-memory, file-backed, or app-storage state.
  static var isolatedSharedState: Self { SharedStateIsolationTrait() }
}
