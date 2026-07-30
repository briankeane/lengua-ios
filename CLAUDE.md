# Lengua iOS

## ALWAYS use the Point-Free Workflow (pfw-*) skills

This project is built on Point-Free libraries (`swift-dependencies`,
`swift-sharing`, `swift-identified-collections`, `swift-custom-dump`, etc.).
Before writing or planning Swift code in this repo, invoke every `pfw-*`
skill that applies to the task. This is **mandatory**, not optional.

Rough mapping:
- Writing or editing `APIClient` / any `@DependencyClient` / anything using
  `@Dependency` → `pfw-dependencies`
- Writing or editing an `@Observable` model (any `*Model.swift` /
  `*Page.swift` model type under `Views/Pages/`) → `pfw-observable-models`
- Writing tests (especially mutation/action tests) → `pfw-testing` AND
  `pfw-custom-dump` (use `expectDifference` / `expectNoDifference`, not raw
  `#expect(a == b)` for value comparisons)
- Adding or editing `@Shared` keys / state (`Lengua/State/*.swift`) →
  `pfw-sharing`
- Working with `IdentifiedArrayOf<…>` → `pfw-identified-collections`
- Asserting on enum cases with associated values → `pfw-case-paths`
- SwiftUI views (bindings, `@State` init, modern patterns) →
  `pfw-modern-swiftui`
- Error reporting (`reportIssue`, `withErrorReporting`) →
  `pfw-issue-reporting`
- Snapshot testing → `pfw-snapshot-testing`

If you are dispatching subagents (via `superpowers:subagent-driven-development`
or similar), instruct each subagent to invoke the relevant pfw skills before
writing code, and reference them in their checklist.

## Server / API documentation

The Lengua server monorepo is expected at `~/code/lengua/server` (sibling
checkout, not inside this repo). If it isn't there, ask the user for the
path before guessing at endpoint shapes or request/response payloads.

## Testing

- **Write tests first when possible** — prefer TDD, write regression tests
  for bug fixes.
- **Tests are app-hosted** — the `LenguaTests` target runs inside the
  `Lengua` app host, via `xcodebuild test` (`make test`).
- **Framework**: always **swift-testing** (`import Testing`, `@Suite` /
  `@Test`, `#expect` / `#require`) — never XCTest. Convert any XCTest file you
  touch. Use `expectNoDifference` / `expectDifference` from CustomDump for value
  comparisons (see the `pfw-custom-dump` skill), not raw `#expect(a == b)`.
- **Test naming**: `@Test` methods are camelCase without underscores and drop
  the `test` prefix (e.g. `greetingUsesFirstNameWhenLoggedIn`).
- **Suites are structs** annotated `@MainActor`. Mark suites that touch
  process-global `@Shared` state `.serialized` to avoid parallel-execution
  races.
- **Tests colocated with code**: `HomePage.swift` → `HomePageTests.swift`.

### Testing with @Shared state

Declare `@Shared` locally inside each test method with an initial value:

```swift
@Test func something() {
  @Shared(.auth) var auth = Auth()
  @Shared(.activeTab) var activeTab = .home

  let model = SomeModel()
  // test...
}
```

Do NOT use class-level `@Shared` properties or `$shared.withLock` in tests
unless the test is specifically exercising the write path.

### Test anti-patterns

- **NEVER use `Task.sleep` in tests** — it makes tests slow and flaky. Use
  synchronous assertions or test doubles that execute synchronously.

## Architecture

**Pattern**: MV with `@Observable` models (not MVVM) — see
`Lengua/Views/Reusable Components/ViewModel.swift` for the shared base type.

### Model structure

Models should be organized with the following `// MARK:` sections in order:

```swift
@MainActor
@Observable
final class SomePageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  init() { }

  // MARK: - Properties
  var isLoading = false
  var presentedAlert: LenguaAlert?

  // MARK: - User Actions
  func viewAppeared() async { }
  func rowTapped(_ item: Item) async { }

  // MARK: - View Helpers
  func isSelected(_ itemId: String) -> Bool { }

  // MARK: - Private Helpers
  private func fetchItems() async { }
}
```

### Model/View responsibilities

**The Model is the complete, portable representation of the page.** If we
port to another platform (Android, web, etc.), only the View should need to
be rebuilt. The Model contains everything: all text, all behavior, all
state.

**Model responsibilities (everything except visuals):**
- All display text (navigation titles, labels, button text, empty states,
  error messages)
- All computed display values (formatted dates, durations, percentages)
- All business logic and state management
- All action handlers (what happens when the user taps something)
- Validation logic and error states

**View responsibilities (visuals only):**
- Layout, spacing, colors, fonts
- Binds to model properties for ALL content (never hardcode strings)
- Calls model methods for ALL user actions
- Contains zero logic — not even simple conditionals about what text to show

**Example — the Model provides everything:**

```swift
// Model
var navigationTitle: String { "Home" }
var greeting: String { auth.currentUser?.firstName.map { "Hi, \($0)!" } ?? "Hi there!" }
```

```swift
// View — just renders what Model provides
Text(model.greeting)   // Good
Text("Hi there!")      // Bad - hardcoded string
```

**Action method naming** — use names that describe user actions:

```swift
// Good - describes what the user did
func signInButtonTapped() async { }

// Bad - describes implementation
func performSignIn() async { }
```

## Dependencies

Uses Point-Free's `swift-dependencies` library:

- Inject via `@Dependency(\.serviceName)` (e.g. `\.api`, `\.analytics`,
  `\.authClient`).
- Mock in tests via `withDependencies { $0.api = ... }`.
- All clients are `Sendable` structs, typically `@DependencyClient`.

## State management

Uses Point-Free's `swift-sharing` library. Keys live in
`Lengua/State/SharedUserDefaults.swift`:

- `@Shared(.auth)` — persisted auth state (file storage)
- `@Shared(.activeTab)` — in-memory active tab selection
- `@Shared(.mainContainerNavigationCoordinator)` — navigation coordinator
- `@Shared(.appVersionRequirements)` — in-memory minimum-version gate

## Project structure

```
Lengua/
├── Config/         # Config.swift + Secrets*.xcconfig
├── Core/
│   ├── API/            # APIClient dependency + live implementation
│   ├── Analytics/      # AnalyticsClient dependency
│   ├── Auth/           # AuthClient dependency
│   ├── ErrorReporting/ # Sentry setup
│   └── Navigation/     # MainContainerNavigationCoordinator
├── Extensions/     # Bundle+Version, etc.
├── Models/         # Codable data models
├── State/          # @Shared state keys
└── Views/
    ├── Pages/                  # Each page: Model + View (+ colocated Tests)
    └── Reusable Components/    # ViewModel base, LenguaAlert, etc.
```

## Code style

- **Linting**: SwiftLint (`.swiftlint.yml`). Run `make lint`.
- **Formatting**: `xcrun swift-format` (`.swiftformat`). Run `make format` to
  rewrite, `make format-check` to verify without rewriting.
- A pre-commit hook (`.githooks/pre-commit`) formats and lints staged files
  automatically once enabled via `git config core.hooksPath .githooks`.

## Conventions

- All view models inherit from the `ViewModel` base class.
- All view models and tests are `@MainActor`.
- Use `async/await`, no completion handlers.
- Alerts via the `LenguaAlert` enum.
- Navigation via `MainContainerNavigationCoordinator` (`push` / `pop` /
  `popToRoot` over a `Path` enum).
