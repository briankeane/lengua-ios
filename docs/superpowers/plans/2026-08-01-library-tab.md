# Library Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder "Deck" tab with a read-only "Library" tab that lists all of the user's vocab items (sortable alphabetically / by date / by familiarity), backed by app-wide shared vocab state that loads on sign-in + foreground and clears on sign-out.

**Architecture:** `VocabItem` Codable model + a thin single-page `APIClient.getVocabItems`. Vocab items live in an in-memory `@Shared(.vocabItems)` value (`VocabItems` struct with items + load flags). A `VocabItemsClient` dependency owns the load-all loop; `ContentViewModel` drives it from auth + scenePhase. `LibraryPageModel` reads the shared state and sorts; `LibraryPage` renders it.

**Tech Stack:** SwiftUI, Point-Free `swift-dependencies` / `swift-sharing` / `swift-identified-collections`, Alamofire, swift-testing + CustomDump.

## Global Constraints

- **Point-Free Workflow (pfw-*) skills are mandatory** before writing Swift: `pfw-observable-models` (models), `pfw-dependencies` (clients), `pfw-sharing` (`@Shared`), `pfw-identified-collections` (`IdentifiedArrayOf`), `pfw-testing` + `pfw-custom-dump` (tests). Each subagent invokes the relevant ones first.
- **Tests use swift-testing only** — `import Testing`, `@Suite`/`@Test`, `@MainActor` structs. Convert any XCTest file you touch. Use `expectNoDifference` / `expectDifference`, never raw `#expect(a == b)` for value comparisons.
- **Suites touching process-global `@Shared` state are `@MainActor` and `.serialized`.** Declare `@Shared` locally per test with an initial value (e.g. `@Shared(.auth) var auth = Auth(jwtToken: "t")`), matching `YouPageModelTests` / `SignInPageTests`.
- **Test naming:** camelCase, no `test` prefix, no underscores.
- **Tests colocated:** `LenguaTests/<Name>Tests.swift`.
- **MV rules:** the Model owns every string and all behavior; the View has zero logic and zero hardcoded strings.
- **Model MARK order:** Dependencies → Shared State → Initialization → Properties → User Actions → View Helpers → Private Helpers.
- **`make test` / `make format` / `make lint`** before each commit. This project uses **XcodeGen** (`project.yml`, whole-folder sources); `make test` runs `xcodegen generate` first, so new files under `Lengua/` and `LenguaTests/` are auto-included — no `.pbxproj` step. The `.xcodeproj` is generated; do not commit it.
- **No `Task.sleep` in tests.** Use synchronous test doubles.
- Endpoint contract: `limit` 1–100 default 50; `cursor` opaque; `nextCursor == null` ends; timestamps ISO8601 with fractional ms + `Z`; `lastSeenAt`/`nextDueAt`/`lastOutcome` nullable; counts non-null ints.
- **Shared vocab state is in-memory** (`InMemoryKey`), not file-backed.

---

### Task 1: `VocabItem` model + fractional-ISO8601 decoder

**Files:**
- Create: `Lengua/Models/VocabItem.swift`
- Create: `Lengua/Extensions/JSONDecoder+Lengua.swift`
- Test: `LenguaTests/VocabItemTests.swift`

**Interfaces:**
- Produces: `struct VocabItem: Codable, Equatable, Sendable, Identifiable`; `extension JSONDecoder { static var lenguaISO8601: JSONDecoder }`.

- [ ] **Step 1: Write the failing decoding tests** — create `LenguaTests/VocabItemTests.swift`:

```swift
import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
struct VocabItemTests {
  private func decode(_ json: String) throws -> VocabItem {
    try JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: Data(json.utf8))
  }

  @Test func decodesFullPayloadWithFractionalSeconds() throws {
    let item = try decode(
      """
      {
        "id": "b1c3f9e2", "targetLanguageCode": "es",
        "sourceText": "dog", "targetText": "perro", "familiarity": 3,
        "lastSeenAt": "2026-08-01T10:00:00.500Z", "timesSeen": 4,
        "timesCorrect": 3, "timesIncorrect": 1, "lastOutcome": "correct",
        "nextDueAt": "2026-08-02T10:00:00.000Z",
        "createdAt": "2026-08-01T10:00:00.000Z",
        "updatedAt": "2026-08-01T10:00:00.000Z"
      }
      """)
    expectNoDifference(item.id, "b1c3f9e2")
    expectNoDifference(item.targetText, "perro")
    expectNoDifference(item.sourceText, "dog")
    expectNoDifference(item.familiarity, 3)
    expectNoDifference(item.lastOutcome, "correct")
    expectNoDifference(item.timesSeen, 4)
    expectNoDifference(item.createdAt, Date(timeIntervalSince1970: 1_754_042_400))
  }

  @Test func decodesNullOptionalsAndZeroCounts() throws {
    let item = try decode(
      """
      {
        "id": "x1", "targetLanguageCode": "es",
        "sourceText": "cat", "targetText": "gato", "familiarity": 0,
        "lastSeenAt": null, "timesSeen": 0, "timesCorrect": 0,
        "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null,
        "createdAt": "2026-08-01T10:00:00.000Z",
        "updatedAt": "2026-08-01T10:00:00.000Z"
      }
      """)
    expectNoDifference(item.lastSeenAt, nil)
    expectNoDifference(item.nextDueAt, nil)
    expectNoDifference(item.lastOutcome, nil)
    expectNoDifference(item.familiarity, 0)
  }

  @Test func decodesTimestampWithoutFractionalSeconds() throws {
    let item = try decode(
      """
      {
        "id": "x2", "targetLanguageCode": "es",
        "sourceText": "cat", "targetText": "gato", "familiarity": 1,
        "lastSeenAt": null, "timesSeen": 0, "timesCorrect": 0,
        "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null,
        "createdAt": "2026-08-01T10:00:00Z", "updatedAt": "2026-08-01T10:00:00Z"
      }
      """)
    expectNoDifference(item.createdAt, Date(timeIntervalSince1970: 1_754_042_400))
  }

  @Test func throwsOnUnparseableDate() {
    #expect(throws: DecodingError.self) {
      try decode(
        """
        {
          "id": "x3", "targetLanguageCode": "es",
          "sourceText": "cat", "targetText": "gato", "familiarity": 0,
          "lastSeenAt": null, "timesSeen": 0, "timesCorrect": 0,
          "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null,
          "createdAt": "not-a-date", "updatedAt": "not-a-date"
        }
        """)
    }
  }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL (types missing).

- [ ] **Step 3: Create the model** — `Lengua/Models/VocabItem.swift`:

```swift
import Foundation

struct VocabItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
  let familiarity: Int
  let lastSeenAt: Date?
  let timesSeen: Int
  let timesCorrect: Int
  let timesIncorrect: Int
  let lastOutcome: String?
  let nextDueAt: Date?
  let createdAt: Date
  let updatedAt: Date
}
```

- [ ] **Step 4: Create the decoder** — `Lengua/Extensions/JSONDecoder+Lengua.swift`:

```swift
import Foundation

extension JSONDecoder {
  /// Decoder for Lengua API payloads whose timestamps are ISO8601 with a `Z`
  /// zone, with or without fractional seconds (`2026-08-01T10:00:00.000Z`).
  /// The stock `.iso8601` strategy rejects the fractional-seconds form.
  static var lenguaISO8601: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let string = try decoder.singleValueContainer().decode(String.self)
      if let date = fractionalFormatter.date(from: string) { return date }
      if let date = plainFormatter.date(from: string) { return date }
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid ISO8601 date: \(string)"))
    }
    return decoder
  }

  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let plainFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
```

- [ ] **Step 5: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Models/VocabItem.swift Lengua/Extensions/JSONDecoder+Lengua.swift LenguaTests/VocabItemTests.swift
git commit -m "feat: add VocabItem model and fractional ISO8601 decoder"
```

---

### Task 2: `APIClient.getVocabItems` endpoint

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift`
- Modify: `Lengua/Core/API/APIClient+Live.swift`
- Test: `LenguaTests/APIClientTests.swift`

**Interfaces:**
- Consumes: `VocabItem`, `JSONDecoder.lenguaISO8601` (Task 1).
- Produces: `struct VocabItemsPage: Equatable, Sendable { var items: [VocabItem]; var nextCursor: String? }`; `APIClient.getVocabItems: @Sendable (_ targetLanguageCode: String?, _ limit: Int?, _ cursor: String?) async throws -> VocabItemsPage` (call positionally: `api.getVocabItems(nil, 100, cursor)`); internal `struct VocabItemsResponse`.

- [ ] **Step 1: Write the failing tests** — add inside the existing `APIClientTests` struct in `LenguaTests/APIClientTests.swift`:

```swift
  @Test func getVocabItemsUsesInjectedDependency() async throws {
    let page = try await withDependencies {
      $0.api.getVocabItems = { languageCode, limit, cursor in
        expectNoDifference(languageCode, nil)
        expectNoDifference(limit, 100)
        expectNoDifference(cursor, nil)
        return VocabItemsPage(
          items: [
            VocabItem(
              id: "1", targetLanguageCode: "es", sourceText: "dog",
              targetText: "perro", familiarity: 0, lastSeenAt: nil,
              timesSeen: 0, timesCorrect: 0, timesIncorrect: 0,
              lastOutcome: nil, nextDueAt: nil,
              createdAt: Date(timeIntervalSince1970: 0),
              updatedAt: Date(timeIntervalSince1970: 0))
          ],
          nextCursor: "next-token")
      }
    } operation: {
      @Dependency(\.api) var api
      return try await api.getVocabItems(nil, 100, nil)
    }
    expectNoDifference(page.items.map(\.id), ["1"])
    expectNoDifference(page.nextCursor, "next-token")
  }

  @Test func vocabItemsResponseDecodesEnvelope() throws {
    let json = Data(
      """
      {
        "vocabItems": [
          { "id": "1", "targetLanguageCode": "es", "sourceText": "dog",
            "targetText": "perro", "familiarity": 2, "lastSeenAt": null,
            "timesSeen": 0, "timesCorrect": 0, "timesIncorrect": 0,
            "lastOutcome": null, "nextDueAt": null,
            "createdAt": "2026-08-01T10:00:00.000Z",
            "updatedAt": "2026-08-01T10:00:00.000Z" }
        ],
        "pagination": { "limit": 50, "nextCursor": null }
      }
      """.utf8)
    let decoded = try JSONDecoder.lenguaISO8601.decode(VocabItemsResponse.self, from: json)
    expectNoDifference(decoded.vocabItems.map(\.targetText), ["perro"])
    expectNoDifference(decoded.pagination.nextCursor, nil)
  }
```

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL (types missing).

- [ ] **Step 3: Declare endpoint, page, envelope** — in `Lengua/Core/API/APIClient.swift`, add to the `@DependencyClient struct APIClient` after `signInViaGoogle`:

```swift
  /// Fetches one page of the caller's vocab items (auth required).
  var getVocabItems: @Sendable (
    _ targetLanguageCode: String?,
    _ limit: Int?,
    _ cursor: String?
  ) async throws -> VocabItemsPage
```

Add near `GoogleSignInResult`:

```swift
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
```

- [ ] **Step 4: Implement the live endpoint** — in `Lengua/Core/API/APIClient+Live.swift`, add `import Sharing` at the top, then add this closure to the `APIClient(...)` initializer (comma after the previous `signInViaGoogle` closure):

```swift
      getVocabItems: { targetLanguageCode, limit, cursor in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken else {
          throw APIError.validationError("You need to be signed in to view your library.")
        }

        let url = baseUrl.appendingPathComponent("v1/vocab-items")
        var parameters: [String: Any] = ["limit": limit ?? 50]
        if let targetLanguageCode { parameters["targetLanguageCode"] = targetLanguageCode }
        if let cursor { parameters["cursor"] = cursor }

        let response = await session.request(
          url,
          parameters: parameters,
          encoding: URLEncoding.default,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let httpResponse = response.response,
          (200..<300).contains(httpResponse.statusCode),
          let data = response.data
        else { throw APIError.dataNotValid }

        guard let decoded = try? JSONDecoder.lenguaISO8601.decode(
          VocabItemsResponse.self, from: data)
        else { throw APIError.dataNotValid }

        return VocabItemsPage(
          items: decoded.vocabItems, nextCursor: decoded.pagination.nextCursor)
      }
```

- [ ] **Step 5: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Core/API/APIClient.swift Lengua/Core/API/APIClient+Live.swift LenguaTests/APIClientTests.swift
git commit -m "feat: add getVocabItems API endpoint with bearer auth"
```

---

### Task 3: Shared `VocabItems` state + `VocabItemsClient`

**Files:**
- Create: `Lengua/State/VocabItems.swift`
- Modify: `Lengua/State/SharedUserDefaults.swift` (add `.vocabItems` key)
- Create: `Lengua/Core/VocabItems/VocabItemsClient.swift`
- Test: `LenguaTests/VocabItemsClientTests.swift`

**Interfaces:**
- Consumes: `VocabItem`, `APIClient.getVocabItems`, `@Shared(.auth)`.
- Produces: `struct VocabItems: Equatable, Sendable { var items: IdentifiedArrayOf<VocabItem>; var isLoading: Bool; var loadFailed: Bool }`; `@Shared(.vocabItems)` in-memory key; `@DependencyClient struct VocabItemsClient: Sendable { var refresh: @Sendable () async -> Void; var clear: @Sendable () -> Void }`; `DependencyValues.vocabItemsClient`.

- [ ] **Step 1: Write the failing tests** — create `LenguaTests/VocabItemsClientTests.swift`:

```swift
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import IdentifiedCollections
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct VocabItemsClientTests {
  private func item(id: String, familiarity: Int = 0) -> VocabItem {
    VocabItem(
      id: id, targetLanguageCode: "es", sourceText: "s", targetText: "t",
      familiarity: familiarity, lastSeenAt: nil, timesSeen: 0, timesCorrect: 0,
      timesIncorrect: 0, lastOutcome: nil, nextDueAt: nil,
      createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
  }

  @Test func refreshLoadsAllPagesIntoSharedState() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, cursor in
        cursor == nil
          ? VocabItemsPage(items: [self.item(id: "1")], nextCursor: "c2")
          : VocabItemsPage(items: [self.item(id: "2")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.items.map(\.id), ["1", "2"])
      expectNoDifference(vocabItems.isLoading, false)
      expectNoDifference(vocabItems.loadFailed, false)
    }
  }

  @Test func refreshFailureSetsLoadFailed() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw APIError.dataNotValid }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.loadFailed, true)
      expectNoDifference(vocabItems.isLoading, false)
      expectNoDifference(vocabItems.items.isEmpty, true)
    }
  }

  @Test func refreshCancellationDoesNotSetLoadFailed() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw CancellationError() }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.loadFailed, false)
      expectNoDifference(vocabItems.isLoading, false)
    }
  }

  @Test func refreshDiscardsResultsIfSignedOutMidLoad() async {
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        @Shared(.auth) var auth
        $auth.withLock { $0 = Auth() }  // sign out during the load
        return VocabItemsPage(items: [self.item(id: "1")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems()
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()

      expectNoDifference(vocabItems.items.isEmpty, true)
      expectNoDifference(vocabItems.isLoading, false)
    }
  }

  @Test func refreshIsCoalescedWhileAlreadyLoading() async {
    let callCount = LockIsolated(0)
    await withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        callCount.withValue { $0 += 1 }
        return VocabItemsPage(items: [self.item(id: "1")], nextCursor: nil)
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(isLoading: true)  // pretend a load is in flight
      @Dependency(\.vocabItemsClient) var client

      await client.refresh()  // should no-op because isLoading == true

      expectNoDifference(callCount.value, 0)
    }
  }

  @Test func clearResetsSharedState() {
    withDependencies {
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(
        items: [item(id: "1")], isLoading: true, loadFailed: true)
      @Dependency(\.vocabItemsClient) var client

      client.clear()

      expectNoDifference(vocabItems, VocabItems())
    }
  }
}
```

> `VocabItems` must expose a memberwise init with defaults so tests can build `VocabItems(isLoading: true)` etc. A plain struct with default values on every stored property gives this automatically.

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL (types missing).

- [ ] **Step 3: Create the shared state struct** — `Lengua/State/VocabItems.swift`:

```swift
import Foundation
import IdentifiedCollections

/// App-wide vocab items plus their load status. In-memory shared state
/// (`@Shared(.vocabItems)`); the server is the source of truth.
struct VocabItems: Equatable, Sendable {
  var items: IdentifiedArrayOf<VocabItem> = []
  var isLoading = false
  var loadFailed = false
}
```

- [ ] **Step 4: Register the shared key** — in `Lengua/State/SharedUserDefaults.swift`, add:

```swift
extension SharedKey where Self == InMemoryKey<VocabItems>.Default {
  static var vocabItems: Self {
    Self[.inMemory("vocabItems"), default: VocabItems()]
  }
}
```

- [ ] **Step 5: Create the client** — `Lengua/Core/VocabItems/VocabItemsClient.swift`:

```swift
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
            state.items = IdentifiedArray(uniqueElements: loaded)
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
```

- [ ] **Step 6: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
make lint
git add Lengua/State/VocabItems.swift Lengua/State/SharedUserDefaults.swift \
  Lengua/Core/VocabItems/VocabItemsClient.swift LenguaTests/VocabItemsClientTests.swift
git commit -m "feat: add shared VocabItems state and VocabItemsClient"
```

---

### Task 4: `ContentViewModel` — sign-in / foreground / sign-out lifecycle

**Files:**
- Modify: `Lengua/Views/Pages/ContentView.swift` (add model + wiring)
- Test: `LenguaTests/ContentViewModelTests.swift`

**Interfaces:**
- Consumes: `VocabItemsClient` (Task 3), `@Shared(.auth)`.
- Produces: `@MainActor @Observable final class ContentViewModel: ViewModel` with `var isLoggedIn: Bool`, `func authStateChanged() async`, `func appEnteredForeground() async`.

- [ ] **Step 1: Write the failing tests** — create `LenguaTests/ContentViewModelTests.swift`:

```swift
import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct ContentViewModelTests {
  @Test func authStateChangedRefreshesWhenLoggedIn() async {
    let refreshes = LockIsolated(0)
    let clears = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
      $0.vocabItemsClient.clear = { clears.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      return ContentViewModel()
    }

    await model.authStateChanged()

    expectNoDifference(refreshes.value, 1)
    expectNoDifference(clears.value, 0)
  }

  @Test func authStateChangedClearsWhenLoggedOut() async {
    let refreshes = LockIsolated(0)
    let clears = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
      $0.vocabItemsClient.clear = { clears.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth()
      return ContentViewModel()
    }

    await model.authStateChanged()

    expectNoDifference(clears.value, 1)
    expectNoDifference(refreshes.value, 0)
  }

  @Test func foregroundRefreshesWhenLoggedIn() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      return ContentViewModel()
    }

    await model.appEnteredForeground()

    expectNoDifference(refreshes.value, 1)
  }

  @Test func foregroundIsNoOpWhenLoggedOut() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.auth) var auth = Auth()
      return ContentViewModel()
    }

    await model.appEnteredForeground()

    expectNoDifference(refreshes.value, 0)
  }

  @Test func isLoggedInReflectsAuth() {
    @Shared(.auth) var auth = Auth(jwtToken: "t")
    expectNoDifference(ContentViewModel().isLoggedIn, true)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL (`ContentViewModel` missing).

- [ ] **Step 3: Add the model + wire ContentView** — replace `Lengua/Views/Pages/ContentView.swift` with:

```swift
import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ContentViewModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - View Helpers
  var isLoggedIn: Bool { auth.isLoggedIn }

  // MARK: - User Actions
  func authStateChanged() async {
    if auth.isLoggedIn {
      await vocabItemsClient.refresh()
    } else {
      vocabItemsClient.clear()
    }
  }

  func appEnteredForeground() async {
    guard auth.isLoggedIn else { return }
    await vocabItemsClient.refresh()
  }
}

@MainActor
struct ContentView: View {
  @State var model = ContentViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var mainContainerModel = MainContainerModel()
  var signInModel = SignInPageModel()

  var body: some View {
    Group {
      if model.isLoggedIn {
        MainContainer(model: mainContainerModel)
      } else {
        SignInPage(model: signInModel)
      }
    }
    .translatorHost()
    .task(id: model.isLoggedIn) { await model.authStateChanged() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.appEnteredForeground() }
      }
    }
  }
}
```

> `ContentView` previously read `@Shared(.auth)` directly and had no `@State`. The model now owns auth; keep `mainContainerModel` / `signInModel` as before. `.task(id: model.isLoggedIn)` re-runs whenever login state flips (sign-in load, sign-out clear) and on first appear (cold-launch load).

- [ ] **Step 4: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
make lint
git add Lengua/Views/Pages/ContentView.swift LenguaTests/ContentViewModelTests.swift
git commit -m "feat: load vocab items on sign-in and foreground, clear on sign-out"
```

---

### Task 5: Rename Deck tab → Library tab (placeholder)

Pure rename so the app compiles and shows a "Library" tab; real logic lands in Task 6.

**Files:**
- Delete: `Lengua/Views/Pages/DeckPage.swift`
- Create: `Lengua/Views/Pages/LibraryPage.swift`
- Modify: `Lengua/Views/Pages/MainContainer.swift`
- Delete: `LenguaTests/DeckPageModelTests.swift`
- Create: `LenguaTests/LibraryPageModelTests.swift`
- Modify: `LenguaTests/MainContainerModelTests.swift`

- [ ] **Step 1: Update the tests first** — delete `LenguaTests/DeckPageModelTests.swift`. Create `LenguaTests/LibraryPageModelTests.swift`:

```swift
import CustomDump
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct LibraryPageModelTests {
  @Test func navigationTitleIsLibrary() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(LibraryPageModel().navigationTitle, "Library")
  }
}
```

Rewrite `LenguaTests/MainContainerModelTests.swift` as swift-testing with Library:

```swift
import CustomDump
import Testing

@testable import Lengua

@MainActor
struct MainContainerModelTests {
  @Test func activeTabHasFiveExpectedCases() {
    expectNoDifference(
      MainContainerModel.ActiveTab.allCases,
      [.lookUp, .library, .review, .talk, .you])
  }

  @Test func tabTitles() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabTitle, "Look up")
    expectNoDifference(model.libraryTabTitle, "Library")
    expectNoDifference(model.reviewTabTitle, "Review")
    expectNoDifference(model.talkTabTitle, "Talk")
    expectNoDifference(model.youTabTitle, "You")
  }

  @Test func tabIconNames() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabIconName, "magnifyingglass")
    expectNoDifference(model.libraryTabIconName, "books.vertical")
    expectNoDifference(model.reviewTabIconName, "checkmark.square")
    expectNoDifference(model.talkTabIconName, "waveform")
    expectNoDifference(model.youTabIconName, "person")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL.

- [ ] **Step 3: Create the placeholder LibraryPage** — delete `Lengua/Views/Pages/DeckPage.swift`. Create `Lengua/Views/Pages/LibraryPage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class LibraryPageModel: ViewModel {

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - View Helpers
  var navigationTitle: String { "Library" }
}

struct LibraryPage: View {
  @State var model: LibraryPageModel

  var body: some View {
    Text(model.navigationTitle)
      .font(.largeTitle)
      .navigationTitle(model.navigationTitle)
  }
}
```

- [ ] **Step 4: Rewire the tab** — in `Lengua/Views/Pages/MainContainer.swift`: rename enum case `case deck` → `case library`; replace lines 17-18 with:

```swift
  var libraryTabTitle: String { "Library" }
  var libraryTabIconName: String { "books.vertical" }
```

Replace the Deck `TabView` block:

```swift
      NavigationStack {
        LibraryPage(model: LibraryPageModel())
      }
      .tabItem { Label(model.libraryTabTitle, systemImage: model.libraryTabIconName) }
      .tag(MainContainerModel.ActiveTab.library)
```

- [ ] **Step 5: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift Lengua/Views/Pages/MainContainer.swift \
  LenguaTests/LibraryPageModelTests.swift LenguaTests/MainContainerModelTests.swift
git add -u Lengua/Views/Pages/DeckPage.swift LenguaTests/DeckPageModelTests.swift
git commit -m "refactor: rename Deck tab to Library placeholder"
```

---

### Task 6: `LibraryPageModel` — read shared state, sort, retry

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (flesh out the model)
- Test: `LenguaTests/LibraryPageModelTests.swift` (full coverage)

**Interfaces:**
- Consumes: `@Shared(.vocabItems)`, `VocabItemsClient.refresh`, `VocabItem`.
- Produces on `LibraryPageModel`: `sortMode: SortMode`; derived `sortedItems: [VocabItem]`, `isLoading: Bool`, `isEmptyStateVisible: Bool`, `showsRetry: Bool`; `familiarityMaxLevel: Int`, `func familiarityLevel(for:) -> Int`, `func sortModeLabel(_:) -> String`, `sortModes: [SortMode]`, `navigationTitle`, `emptyStateText`, `retryButtonTitle`, `sortMenuTitle`; `func retryButtonTapped() async`; `enum SortMode: String, CaseIterable, Sendable { case date, alphabetical, familiarity }`.

- [ ] **Step 1: Write the failing tests** — replace the body of `LenguaTests/LibraryPageModelTests.swift`:

```swift
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized)
struct LibraryPageModelTests {
  private func item(
    id: String, target: String = "x", source: String = "y",
    familiarity: Int = 0, created: TimeInterval = 0
  ) -> VocabItem {
    VocabItem(
      id: id, targetLanguageCode: "es", sourceText: source, targetText: target,
      familiarity: familiarity, lastSeenAt: nil, timesSeen: 0, timesCorrect: 0,
      timesIncorrect: 0, lastOutcome: nil, nextDueAt: nil,
      createdAt: Date(timeIntervalSince1970: created),
      updatedAt: Date(timeIntervalSince1970: created))
  }

  @Test func navigationTitleIsLibrary() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(LibraryPageModel().navigationTitle, "Library")
  }

  @Test func readsLoadingFromSharedState() {
    @Shared(.vocabItems) var vocabItems = VocabItems(isLoading: true)
    expectNoDifference(LibraryPageModel().isLoading, true)
  }

  @Test func emptyStateVisibleWhenLoadedAndEmpty() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = LibraryPageModel()
    expectNoDifference(model.isEmptyStateVisible, true)
    expectNoDifference(model.showsRetry, false)
  }

  @Test func retryVisibleOnFailureWithNoItems() {
    @Shared(.vocabItems) var vocabItems = VocabItems(loadFailed: true)
    let model = LibraryPageModel()
    expectNoDifference(model.showsRetry, true)
    expectNoDifference(model.isEmptyStateVisible, false)
  }

  @Test func retryButtonTappedCallsRefresh() async {
    let refreshes = LockIsolated(0)
    let model = withDependencies {
      $0.vocabItemsClient.refresh = { refreshes.withValue { $0 += 1 } }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems()
      return LibraryPageModel()
    }

    await model.retryButtonTapped()

    expectNoDifference(refreshes.value, 1)
  }

  @Test func alphabeticalSortIsCaseInsensitiveByTargetText() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "1", target: "banana"), item(id: "2", target: "Apple"),
        item(id: "3", target: "cherry"),
      ])
    let model = LibraryPageModel()
    model.sortMode = .alphabetical
    expectNoDifference(model.sortedItems.map(\.targetText), ["Apple", "banana", "cherry"])
  }

  @Test func dateSortIsNewestFirst() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "old", created: 100), item(id: "new", created: 300),
        item(id: "mid", created: 200),
      ])
    let model = LibraryPageModel()
    model.sortMode = .date
    expectNoDifference(model.sortedItems.map(\.id), ["new", "mid", "old"])
  }

  @Test func familiaritySortIsAscending() {
    @Shared(.vocabItems) var vocabItems = VocabItems(
      items: [
        item(id: "known", familiarity: 5), item(id: "new", familiarity: 0),
        item(id: "learning", familiarity: 2),
      ])
    let model = LibraryPageModel()
    model.sortMode = .familiarity
    expectNoDifference(model.sortedItems.map(\.id), ["new", "learning", "known"])
  }

  @Test func familiarityLevelClampsToRange() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = LibraryPageModel()
    expectNoDifference(model.familiarityMaxLevel, 5)
    expectNoDifference(model.familiarityLevel(for: item(id: "a", familiarity: 3)), 3)
    expectNoDifference(model.familiarityLevel(for: item(id: "b", familiarity: 9)), 5)
    expectNoDifference(model.familiarityLevel(for: item(id: "c", familiarity: -1)), 0)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail** — `make test`. Expected: FAIL (members missing).

- [ ] **Step 3: Implement the model** — replace the `LibraryPageModel` class in `Lengua/Views/Pages/LibraryPage.swift` (leave the `LibraryPage` view for Task 7):

```swift
import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class LibraryPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var sortMode: SortMode = .date

  enum SortMode: String, CaseIterable, Sendable {
    case date
    case alphabetical
    case familiarity
  }

  // MARK: - User Actions
  func retryButtonTapped() async {
    await vocabItemsClient.refresh()
  }

  // MARK: - View Helpers
  var navigationTitle: String { "Library" }
  var emptyStateText: String { "You haven't saved any vocab items yet." }
  var retryButtonTitle: String { "Try Again" }
  var sortMenuTitle: String { "Sort" }

  var sortModes: [SortMode] { SortMode.allCases }

  func sortModeLabel(_ mode: SortMode) -> String {
    switch mode {
    case .date: return "Date"
    case .alphabetical: return "Alphabetical"
    case .familiarity: return "Familiarity"
    }
  }

  var isLoading: Bool { vocabItems.isLoading }
  var isEmptyStateVisible: Bool {
    !vocabItems.isLoading && !vocabItems.loadFailed && vocabItems.items.isEmpty
  }
  var showsRetry: Bool { vocabItems.loadFailed && vocabItems.items.isEmpty }

  let familiarityMaxLevel = 5

  func familiarityLevel(for item: VocabItem) -> Int {
    min(max(item.familiarity, 0), familiarityMaxLevel)
  }

  var sortedItems: [VocabItem] {
    switch sortMode {
    case .date:
      return vocabItems.items.sorted { lhs, rhs in
        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id > rhs.id
      }
    case .alphabetical:
      return vocabItems.items.sorted { lhs, rhs in
        let byTarget = lhs.targetText.localizedCaseInsensitiveCompare(rhs.targetText)
        if byTarget != .orderedSame { return byTarget == .orderedAscending }
        let bySource = lhs.sourceText.localizedCaseInsensitiveCompare(rhs.sourceText)
        if bySource != .orderedSame { return bySource == .orderedAscending }
        return lhs.id < rhs.id
      }
    case .familiarity:
      return vocabItems.items.sorted { lhs, rhs in
        lhs.familiarity != rhs.familiarity
          ? lhs.familiarity < rhs.familiarity
          : lhs.createdAt > rhs.createdAt
      }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass** — `make format && make test`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift LenguaTests/LibraryPageModelTests.swift
git commit -m "feat: LibraryPageModel reads shared vocab state and sorts"
```

---

### Task 7: `LibraryPage` view — list, familiarity dots, sort control

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (replace the placeholder view)

**Interfaces:**
- Consumes: every `LibraryPageModel` view helper from Task 6.
- Produces: the finished `LibraryPage` view. No new testable Swift API.

- [ ] **Step 1: Replace the view** — replace the `LibraryPage` struct in `Lengua/Views/Pages/LibraryPage.swift` with:

```swift
struct LibraryPage: View {
  @State var model: LibraryPageModel

  var body: some View {
    List {
      ForEach(model.sortedItems) { item in
        LibraryRow(
          targetText: item.targetText,
          sourceText: item.sourceText,
          filledDots: model.familiarityLevel(for: item),
          totalDots: model.familiarityMaxLevel)
      }
    }
    .overlay {
      if model.isLoading {
        ProgressView()
      } else if model.showsRetry {
        RetryState(message: model.emptyStateText, buttonTitle: model.retryButtonTitle) {
          await model.retryButtonTapped()
        }
      } else if model.isEmptyStateVisible {
        ContentUnavailableView(model.emptyStateText, systemImage: "books.vertical")
      }
    }
    .navigationTitle(model.navigationTitle)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu(model.sortMenuTitle) {
          Picker(model.sortMenuTitle, selection: $model.sortMode) {
            ForEach(model.sortModes, id: \.self) { mode in
              Text(model.sortModeLabel(mode)).tag(mode)
            }
          }
        }
      }
    }
  }
}

private struct LibraryRow: View {
  let targetText: String
  let sourceText: String
  let filledDots: Int
  let totalDots: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(targetText).font(.headline)
        Text(sourceText).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      HStack(spacing: 3) {
        ForEach(0..<totalDots, id: \.self) { index in
          Circle()
            .fill(index < filledDots ? Color.accentColor : Color.secondary.opacity(0.25))
            .frame(width: 7, height: 7)
        }
      }
    }
  }
}

private struct RetryState: View {
  let message: String
  let buttonTitle: String
  let retry: () async -> Void

  var body: some View {
    ContentUnavailableView {
      Label(message, systemImage: "exclamationmark.triangle")
    } actions: {
      Button(buttonTitle) { Task { await retry() } }
    }
  }
}
```

> No load-on-appear: the list reflects `@Shared(.vocabItems)`, which the lifecycle (Task 4) keeps fresh. Retry is the only load the view triggers.

- [ ] **Step 2: Build and run the suite** — `make format && make test`. Expected: PASS (compiles; model tests green).

- [ ] **Step 3: Manual verification** — launch the app. Confirm the tab bar shows "Library" with the books icon; after sign-in / on foreground the list populates (or shows empty/retry); the Sort menu reorders; each row shows target over source with familiarity dots.

- [ ] **Step 4: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift
git commit -m "feat: build Library list view with familiarity dots and sort control"
```

---

## Self-Review

**Spec coverage:**
- VocabItem model + optionals/ints, fractional/plain/null/unparseable date decoding → Task 1. ✅
- Thin single-page `getVocabItems` + `VocabItemsPage` + bearer auth + envelope decode → Task 2. ✅
- Shared in-memory `VocabItems` state + `@Shared(.vocabItems)` + `VocabItemsClient` (load-all, coalescing, error→loadFailed, cancellation, sign-out-mid-load discard, clear) → Task 3. ✅
- Load on sign-in + foreground, clear on sign-out via `ContentViewModel` + `.task(id:)` + scenePhase → Task 4. ✅
- Deck→Library rename (case, title "Library", icon `books.vertical`) + XCTest→swift-testing conversions → Task 5. ✅
- LibraryPageModel reads shared state, three sorts with tie-breaks + defaults, derived loading/empty/retry, retry→refresh, familiarity dots helpers → Task 6. ✅
- List view with target/source + dots, sort control, loading/empty/retry overlays, no load-on-appear → Task 7. ✅
- No language filter (pass nil, param retained) → Tasks 2 & 3. ✅
- Read-only, no detail view → no tap handler anywhere. ✅

**Placeholder scan:** No TBD/TODO; every code step has full code. ✅

**Type consistency:** `getVocabItems(_:_:_:) -> VocabItemsPage`; `VocabItems { items, isLoading, loadFailed }` used identically across Task 3 client, Task 6 model, and all tests; `vocabItemsClient.refresh`/`.clear` names match across Tasks 3/4/6; `SortMode` cases + `familiarityMaxLevel`/`familiarityLevel(for:)` consistent between Task 6 model and Task 7 view. ✅

**Ordering:** Task 3 (client) precedes Tasks 4 & 6 that consume it; Task 5 rename precedes Task 6's model fill-in; each task compiles and is independently testable.
