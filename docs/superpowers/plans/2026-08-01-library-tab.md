# Library Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder "Deck" tab with a read-only "Library" tab that lists all of the user's vocab items, sortable alphabetically / by date / by familiarity.

**Architecture:** New `VocabItem` Codable model + a thin single-page `APIClient.getVocabItems` endpoint. `LibraryPageModel` (an `@Observable` MV model) pages through the endpoint on appear, holds every item in memory, and sorts client-side. `LibraryPage` renders the list with a familiarity-dots indicator and a sort control. Deck files are renamed to Library and the tab is rewired.

**Tech Stack:** SwiftUI, Point-Free `swift-dependencies` / `swift-sharing` / `swift-identified-collections`, Alamofire, swift-testing + CustomDump.

## Global Constraints

- **Point-Free Workflow (pfw-*) skills are mandatory** before writing Swift: `pfw-observable-models` (models), `pfw-dependencies` (APIClient), `pfw-sharing` (`@Shared`), `pfw-identified-collections` (`IdentifiedArrayOf`), `pfw-testing` + `pfw-custom-dump` (tests). Each subagent must invoke the relevant ones first.
- **Tests use swift-testing only** — `import Testing`, `@Suite`/`@Test`, `@MainActor` structs. Convert any XCTest file you touch. Use `expectNoDifference` / `expectDifference`, never raw `#expect(a == b)` for value comparisons.
- **Test naming:** camelCase, no `test` prefix, no underscores (e.g. `loadsAllPages`).
- **Tests colocated:** `LenguaTests/<Name>Tests.swift`.
- **MV rules:** the Model owns every string and all behavior; the View has zero logic and zero hardcoded strings.
- **Model MARK order:** Dependencies → Shared State → Initialization → Properties → User Actions → View Helpers → Private Helpers.
- **Models & tests are `@MainActor`.** Suites touching process-global `@Shared` state are `.serialized`.
- **Run tests with `make test`; format with `make format`; lint with `make lint`** before each commit. The pre-commit hook may also run these.
- **No `Task.sleep` in tests.** Use injected test doubles that execute synchronously.
- Endpoint contract (verbatim): `limit` range 1–100 default 50; `cursor` opaque (never construct/parse); `nextCursor == null` means end; timestamps are ISO8601 with fractional milliseconds and `Z` (`2026-08-01T10:00:00.000Z`); `lastSeenAt`/`nextDueAt`/`lastOutcome` nullable; `familiarity`/`timesSeen`/`timesCorrect`/`timesIncorrect` non-null ints.

---

### Task 1: `VocabItem` model + fractional-ISO8601 decoder

**Files:**
- Create: `Lengua/Models/VocabItem.swift`
- Create: `Lengua/Extensions/JSONDecoder+Lengua.swift`
- Test: `LenguaTests/VocabItemTests.swift`

**Interfaces:**
- Produces: `struct VocabItem: Codable, Equatable, Sendable, Identifiable` with fields listed below; `extension JSONDecoder { static var lenguaISO8601: JSONDecoder { get } }` — a decoder that parses ISO8601 timestamps with or without fractional seconds and throws `DecodingError.dataCorrupted` otherwise.

- [ ] **Step 1: Write the failing decoding tests**

Create `LenguaTests/VocabItemTests.swift`:

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
    expectNoDifference(
      item.createdAt, Date(timeIntervalSince1970: 1_754_042_400))  // 2026-08-01T10:00:00Z
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
        "createdAt": "2026-08-01T10:00:00Z",
        "updatedAt": "2026-08-01T10:00:00Z"
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

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `VocabItem` and `JSONDecoder.lenguaISO8601` do not exist (compile error).

- [ ] **Step 3: Create the model**

`Lengua/Models/VocabItem.swift`:

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

- [ ] **Step 4: Create the decoder**

`Lengua/Extensions/JSONDecoder+Lengua.swift`:

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

- [ ] **Step 5: Run tests to verify they pass**

Run: `make format && make test`
Expected: PASS (all four `VocabItemTests`).

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Models/VocabItem.swift Lengua/Extensions/JSONDecoder+Lengua.swift LenguaTests/VocabItemTests.swift
git commit -m "feat: add VocabItem model and fractional ISO8601 decoder"
```

---

### Task 2: `APIClient.getVocabItems` endpoint

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift` (add `VocabItemsPage` + endpoint declaration)
- Modify: `Lengua/Core/API/APIClient+Live.swift` (live implementation)
- Test: `LenguaTests/APIClientTests.swift` (add cases)

**Interfaces:**
- Consumes: `VocabItem`, `JSONDecoder.lenguaISO8601` (Task 1).
- Produces: `struct VocabItemsPage: Equatable, Sendable { var items: [VocabItem]; var nextCursor: String? }`; `APIClient.getVocabItems: @Sendable (_ targetLanguageCode: String?, _ limit: Int?, _ cursor: String?) async throws -> VocabItemsPage`. Callers invoke positionally: `try await api.getVocabItems(nil, 100, cursor)`.

- [ ] **Step 1: Write the failing tests**

Add to `LenguaTests/APIClientTests.swift` (inside the existing `APIClientTests` struct):

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

> Note: `VocabItemsResponse` is created in Step 3 as an `internal` type so this test can reference it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `getVocabItems`, `VocabItemsPage`, `VocabItemsResponse` do not exist.

- [ ] **Step 3: Declare the endpoint, page, and envelope**

In `Lengua/Core/API/APIClient.swift`, add the endpoint to the `@DependencyClient struct APIClient` (after `signInViaGoogle`):

```swift
  /// Fetches one page of the caller's vocab items (auth required).
  var getVocabItems: @Sendable (
    _ targetLanguageCode: String?,
    _ limit: Int?,
    _ cursor: String?
  ) async throws -> VocabItemsPage
```

Add these types near `GoogleSignInResult` in the same file:

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

- [ ] **Step 4: Implement the live endpoint**

In `Lengua/Core/API/APIClient+Live.swift`, add `import Sharing` at the top, and add this closure to the `APIClient(...)` initializer (after `signInViaGoogle`, add a comma after the previous closure):

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

- [ ] **Step 5: Run tests to verify they pass**

Run: `make format && make test`
Expected: PASS (both new `APIClientTests` cases, existing cases still green).

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Core/API/APIClient.swift Lengua/Core/API/APIClient+Live.swift LenguaTests/APIClientTests.swift
git commit -m "feat: add getVocabItems API endpoint with bearer auth"
```

---

### Task 3: Rename Deck tab → Library tab (placeholder)

Pure rename so the app compiles and shows a "Library" tab; real logic lands in Task 4. This keeps the rename reviewable on its own.

**Files:**
- Delete: `Lengua/Views/Pages/DeckPage.swift`
- Create: `Lengua/Views/Pages/LibraryPage.swift`
- Modify: `Lengua/Views/Pages/MainContainer.swift` (enum case, titles/icons, TabView block)
- Delete: `LenguaTests/DeckPageModelTests.swift`
- Create: `LenguaTests/LibraryPageModelTests.swift` (converted to swift-testing)
- Modify: `LenguaTests/MainContainerModelTests.swift` (convert to swift-testing + update Deck→Library)

- [ ] **Step 1: Update the failing tests first**

Delete `LenguaTests/DeckPageModelTests.swift` (XCTest). Create `LenguaTests/LibraryPageModelTests.swift`:

```swift
import CustomDump
import Testing

@testable import Lengua

@MainActor
struct LibraryPageModelTests {
  @Test func navigationTitleIsLibrary() {
    let model = LibraryPageModel()
    expectNoDifference(model.navigationTitle, "Library")
  }
}
```

Rewrite `LenguaTests/MainContainerModelTests.swift` as swift-testing with Library in place of Deck:

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

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `LibraryPageModel`, `.library`, `libraryTabTitle`, `libraryTabIconName` do not exist.

- [ ] **Step 3: Create the placeholder LibraryPage**

Delete `Lengua/Views/Pages/DeckPage.swift`. Create `Lengua/Views/Pages/LibraryPage.swift`:

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

- [ ] **Step 4: Rewire the tab in MainContainer**

In `Lengua/Views/Pages/MainContainer.swift`:

Rename the enum case (line 9): `case deck` → `case library`.

Replace the title/icon lines (17-18):

```swift
  var libraryTabTitle: String { "Library" }
  var libraryTabIconName: String { "books.vertical" }
```

Replace the Deck `TabView` block (lines 41-45):

```swift
      NavigationStack {
        LibraryPage(model: LibraryPageModel())
      }
      .tabItem { Label(model.libraryTabTitle, systemImage: model.libraryTabIconName) }
      .tag(MainContainerModel.ActiveTab.library)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make format && make test`
Expected: PASS. App compiles; tab shows "Library".

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift Lengua/Views/Pages/MainContainer.swift \
  LenguaTests/LibraryPageModelTests.swift LenguaTests/MainContainerModelTests.swift
git add -u Lengua/Views/Pages/DeckPage.swift LenguaTests/DeckPageModelTests.swift
git commit -m "refactor: rename Deck tab to Library placeholder"
```

---

### Task 4: `LibraryPageModel` — load-all + sorting + state

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (flesh out the model)
- Modify: `Lengua/Views/Reusable Components/LenguaAlert.swift` (add `vocabItemsLoadFailed`)
- Modify: `LenguaTests/LibraryPageModelTests.swift` (full coverage)

**Interfaces:**
- Consumes: `APIClient.getVocabItems` (Task 2), `VocabItem`, `VocabItemsPage`, `LenguaAlert`.
- Produces on `LibraryPageModel`: `items: IdentifiedArrayOf<VocabItem>`, `isLoading: Bool`, `loadDidError: Bool`, `sortMode: SortMode`, `presentedAlert: LenguaAlert?`, `sortedItems: [VocabItem]`, `showsRetry: Bool`, `isEmptyStateVisible: Bool`, `familiarityMaxLevel: Int`, `func familiarityLevel(for:) -> Int`, `func sortModeLabel(_:) -> String`, `sortMenuTitle`, `emptyStateText`, `retryButtonTitle`, `navigationTitle`; `func viewAppeared() async`, `func retryButtonTapped() async`; `enum SortMode: String, CaseIterable, Sendable { case date, alphabetical, familiarity }`.

- [ ] **Step 1: Write the failing tests**

Replace the body of `LenguaTests/LibraryPageModelTests.swift`:

```swift
import CustomDump
import Dependencies
import Foundation
import IdentifiedCollections
import Testing

@testable import Lengua

@MainActor
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
    expectNoDifference(LibraryPageModel().navigationTitle, "Library")
  }

  @Test func loadsAllPagesFollowingCursor() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, cursor in
        switch cursor {
        case nil: return VocabItemsPage(items: [item(id: "1")], nextCursor: "c2")
        case "c2": return VocabItemsPage(items: [item(id: "2")], nextCursor: "c3")
        default: return VocabItemsPage(items: [item(id: "3")], nextCursor: nil)
        }
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()

    expectNoDifference(model.items.map(\.id), ["1", "2", "3"])
    expectNoDifference(model.isLoading, false)
    expectNoDifference(model.loadDidError, false)
  }

  @Test func emptyListShowsEmptyStateNoError() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in VocabItemsPage(items: [], nextCursor: nil) }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()

    expectNoDifference(model.items.isEmpty, true)
    expectNoDifference(model.isEmptyStateVisible, true)
    expectNoDifference(model.presentedAlert, nil)
  }

  @Test func loadFailureSetsAlertAndRetry() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw APIError.dataNotValid }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()

    expectNoDifference(model.presentedAlert, .vocabItemsLoadFailed)
    expectNoDifference(model.loadDidError, true)
    expectNoDifference(model.showsRetry, true)
  }

  @Test func retryReloadsAfterFailure() async {
    let shouldFail = LockIsolated(true)
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        if shouldFail.value { throw APIError.dataNotValid }
        return VocabItemsPage(items: [item(id: "1")], nextCursor: nil)
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()
    expectNoDifference(model.loadDidError, true)

    shouldFail.setValue(false)
    await model.retryButtonTapped()

    expectNoDifference(model.items.map(\.id), ["1"])
    expectNoDifference(model.loadDidError, false)
  }

  @Test func viewAppearedLoadsOnlyOnce() async {
    let calls = LockIsolated(0)
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        calls.withValue { $0 += 1 }
        return VocabItemsPage(items: [item(id: "1")], nextCursor: nil)
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()
    await model.viewAppeared()

    expectNoDifference(calls.value, 1)
  }

  @Test func cancellationDoesNotAlert() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in throw CancellationError() }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()

    expectNoDifference(model.presentedAlert, nil)
    expectNoDifference(model.loadDidError, false)
  }

  @Test func alphabeticalSortIsCaseInsensitiveByTargetText() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        VocabItemsPage(
          items: [
            item(id: "1", target: "banana"), item(id: "2", target: "Apple"),
            item(id: "3", target: "cherry"),
          ], nextCursor: nil)
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()
    model.sortMode = .alphabetical

    expectNoDifference(model.sortedItems.map(\.targetText), ["Apple", "banana", "cherry"])
  }

  @Test func dateSortIsNewestFirst() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        VocabItemsPage(
          items: [
            item(id: "old", created: 100), item(id: "new", created: 300),
            item(id: "mid", created: 200),
          ], nextCursor: nil)
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()
    model.sortMode = .date

    expectNoDifference(model.sortedItems.map(\.id), ["new", "mid", "old"])
  }

  @Test func familiaritySortIsAscending() async {
    let model = withDependencies {
      $0.api.getVocabItems = { _, _, _ in
        VocabItemsPage(
          items: [
            item(id: "known", familiarity: 5), item(id: "new", familiarity: 0),
            item(id: "learning", familiarity: 2),
          ], nextCursor: nil)
      }
    } operation: { LibraryPageModel() }

    await model.viewAppeared()
    model.sortMode = .familiarity

    expectNoDifference(model.sortedItems.map(\.id), ["new", "learning", "known"])
  }

  @Test func familiarityLevelClampsToRange() {
    let model = LibraryPageModel()
    expectNoDifference(model.familiarityMaxLevel, 5)
    expectNoDifference(model.familiarityLevel(for: item(id: "a", familiarity: 3)), 3)
    expectNoDifference(model.familiarityLevel(for: item(id: "b", familiarity: 9)), 5)
    expectNoDifference(model.familiarityLevel(for: item(id: "c", familiarity: -1)), 0)
  }
}
```

Add `import ConcurrencyExtras` at the top if `LockIsolated` is not already resolved (it lives in ConcurrencyExtras, re-exported by Dependencies — match whatever `TranslatePageModelTests.swift` imports; it uses `import ConcurrencyExtras`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — new members and `.vocabItemsLoadFailed` do not exist.

- [ ] **Step 3: Add the alert**

In `Lengua/Views/Reusable Components/LenguaAlert.swift`, add inside the `extension LenguaAlert`:

```swift
  static var vocabItemsLoadFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Load Your Library",
      message: "We couldn't load your vocab items just now. Check your connection and try again.")
  }
```

- [ ] **Step 4: Implement the model**

Replace the `LibraryPageModel` class in `Lengua/Views/Pages/LibraryPage.swift` (keep the `LibraryPage` view untouched for now) with:

```swift
import Dependencies
import IdentifiedCollections
import SwiftUI

@MainActor
@Observable
final class LibraryPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var items: IdentifiedArrayOf<VocabItem> = []
  var isLoading = false
  var loadDidError = false
  var sortMode: SortMode = .date
  var presentedAlert: LenguaAlert?

  @ObservationIgnored private var hasLoaded = false

  enum SortMode: String, CaseIterable, Sendable {
    case date
    case alphabetical
    case familiarity
  }

  // MARK: - User Actions
  func viewAppeared() async {
    guard !hasLoaded, !isLoading else { return }
    hasLoaded = true
    isLoading = true
    loadDidError = false
    defer { isLoading = false }

    do {
      var loaded: [VocabItem] = []
      var cursor: String?
      repeat {
        let page = try await api.getVocabItems(nil, 100, cursor)
        loaded.append(contentsOf: page.items)
        cursor = page.nextCursor
      } while cursor != nil
      items = IdentifiedArray(uniqueElements: loaded)
    } catch is CancellationError {
      hasLoaded = false  // allow a fresh load next time the tab appears
    } catch {
      hasLoaded = false  // allow retry
      loadDidError = true
      presentedAlert = .vocabItemsLoadFailed
    }
  }

  func retryButtonTapped() async {
    await viewAppeared()
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

  var isEmptyStateVisible: Bool { !isLoading && !loadDidError && items.isEmpty }
  var showsRetry: Bool { loadDidError && items.isEmpty }

  let familiarityMaxLevel = 5

  func familiarityLevel(for item: VocabItem) -> Int {
    min(max(item.familiarity, 0), familiarityMaxLevel)
  }

  var sortedItems: [VocabItem] {
    switch sortMode {
    case .date:
      return items.sorted { lhs, rhs in
        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id > rhs.id
      }
    case .alphabetical:
      return items.sorted { lhs, rhs in
        let byTarget = lhs.targetText.localizedCaseInsensitiveCompare(rhs.targetText)
        if byTarget != .orderedSame { return byTarget == .orderedAscending }
        let bySource = lhs.sourceText.localizedCaseInsensitiveCompare(rhs.sourceText)
        if bySource != .orderedSame { return bySource == .orderedAscending }
        return lhs.id < rhs.id
      }
    case .familiarity:
      return items.sorted { lhs, rhs in
        lhs.familiarity != rhs.familiarity
          ? lhs.familiarity < rhs.familiarity
          : lhs.createdAt > rhs.createdAt
      }
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make format && make test`
Expected: PASS (all `LibraryPageModelTests`).

- [ ] **Step 6: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift \
  "Lengua/Views/Reusable Components/LenguaAlert.swift" \
  LenguaTests/LibraryPageModelTests.swift
git commit -m "feat: implement LibraryPageModel load-all and sorting"
```

---

### Task 5: `LibraryPage` view — list, familiarity dots, sort control

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (replace the placeholder view)

**Interfaces:**
- Consumes: every `LibraryPageModel` view helper from Task 4.
- Produces: the finished `LibraryPage` view. No new testable Swift API (SwiftUI layout; covered by the model tests + manual/preview verification).

- [ ] **Step 1: Replace the view**

Replace the `LibraryPage` struct in `Lengua/Views/Pages/LibraryPage.swift` with:

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
    .lenguaAlert($model.presentedAlert)
    .task { await model.viewAppeared() }
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

- [ ] **Step 2: Build and run the test suite**

Run: `make format && make test`
Expected: PASS (compiles; model tests still green).

- [ ] **Step 3: Manual verification**

Launch the app (see the `run` skill / Xcode). Confirm: the tab bar shows a "Library" tab with the books icon; opening it loads items (or shows the empty/retry state); the Sort menu switches ordering; each row shows target over source with familiarity dots.

- [ ] **Step 4: Commit**

```bash
make lint
git add Lengua/Views/Pages/LibraryPage.swift
git commit -m "feat: build Library list view with familiarity dots and sort control"
```

---

## Self-Review

**Spec coverage:**
- VocabItem model + optionals/ints → Task 1. ✅
- Fractional ISO8601 date decoding (+ fallback, null, unparseable) → Task 1. ✅
- Thin single-page `getVocabItems` + `VocabItemsPage` struct + bearer auth + envelope decode → Task 2. ✅
- Load-all loop (limit 100, follow cursor, assign once), re-entrancy guard, cancellation-not-alerted, error alert + retry → Task 4. ✅
- Three sort modes with tie-breaks + defaults (Date newest-first default; Familiarity ascending) → Task 4. ✅
- Row layout target/source + familiarity dots, sort control, loading/empty/retry states → Task 5. ✅
- Tab rename Deck→Library (case, title "Library", icon `books.vertical`, wiring) + XCTest→swift-testing conversions → Task 3. ✅
- No language filter (pass nil, param retained) → Tasks 2 & 4. ✅
- Read-only, no detail view → no tap handler anywhere. ✅

**Placeholder scan:** No TBD/TODO steps; every code step has full code. ✅

**Type consistency:** `getVocabItems(_ targetLanguageCode:_ limit:_ cursor:)` returns `VocabItemsPage` everywhere; `SortMode` cases `date`/`alphabetical`/`familiarity` consistent across model + tests; `familiarityMaxLevel`/`familiarityLevel(for:)` names match between model and Task 5 view. ✅

**Note for the executor:** Xcode project membership — new files under `Lengua/` and `LenguaTests/` must be added to the `Lengua` and `LenguaTests` targets respectively. If the project uses folder-synced groups they are picked up automatically; otherwise add them in Xcode (or the `.pbxproj`) before `make test`.
