# Library Swipe-to-Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user swipe a Library row and tap **Delete** to permanently remove a saved vocab item, waiting for server confirmation before the row disappears.

**Architecture:** Three layers, bottom-up. `APIClient.deleteVocabItem` does the `DELETE` network call. `VocabItemsClient.delete` wraps it and removes the item from `@Shared(.vocabItems)` on success, guarded by the account token. `LibraryPageModel` orchestrates per-row deleting state + failure alert; the `LibraryPage` view converts to a `List` for `.swipeActions`.

**Tech Stack:** SwiftUI, Point-Free swift-dependencies / swift-sharing / swift-identified-collections, Alamofire (network), swift-testing (`import Testing`, `expectNoDifference`).

## Global Constraints

- **Testing framework:** swift-testing only (`import Testing`, `@Suite`, `@Test`, `#expect`/`#require`). Never XCTest. Use `expectNoDifference` from CustomDump for value comparisons, not `#expect(a == b)`.
- **Test suites:** structs annotated `@MainActor`; suites touching process-global `@Shared` state are `.serialized`.
- **Test naming:** camelCase, no underscores, drop the `test` prefix.
- **@Shared in tests:** declare locally inside each test method with an initial value; do not use class-level `@Shared` or `$shared.withLock` unless exercising the write path.
- **No `Task.sleep` in tests.**
- **Architecture:** MV with `@Observable` models. Model holds all text/behavior/state; the View is visuals only and binds to model properties. Model MARK sections in order: Dependencies, Shared State, Initialization, Properties, User Actions, View Helpers, Private Helpers.
- **Action method naming:** describe the user action (`deleteButtonTapped`), not the implementation.
- **Run before committing:** `make format` then `make lint` (or the pre-commit hook). `make test` runs the app-hosted `LenguaTests` via `xcodebuild test`.
- **Server contract:** `DELETE /v1/vocab-items/{id}`, Bearer auth → `204` success (no body), `404` = already gone / not owned (treat as success), `401` unauthenticated, `400` malformed id.

---

## File map

- Modify `Lengua/Core/API/APIClient.swift` — add `deleteVocabItem` to the `@DependencyClient` struct.
- Modify `Lengua/Core/API/APIClient+Live.swift` — add the live `deleteVocabItem` implementation.
- Modify `Lengua/Core/VocabItems/VocabItemsClient.swift` — add `delete` to the client + its live implementation.
- Modify `Lengua/Views/Reusable Components/LenguaAlert.swift` — add `LenguaAlert.deleteFailed`.
- Modify `Lengua/Views/Pages/LibraryPage.swift` — add model state/actions; convert the item list to a `List` with `.swipeActions`.
- Modify `LenguaTests/VocabItemsClientTests.swift` — client delete tests.
- Modify `LenguaTests/LibraryPageModelTests.swift` — model delete tests.

---

## Task 1: `APIClient.deleteVocabItem` (interface + live)

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift` (add to struct, after `saveVocabItem` ~line 29)
- Modify: `Lengua/Core/API/APIClient+Live.swift` (add after the `saveVocabItem` closure ~line 120)

**Interfaces:**
- Produces: `var deleteVocabItem: @Sendable (_ id: String) async throws -> Void` on `APIClient`.

There is no unit test for the live Alamofire layer (it hits the network); it is covered indirectly through `VocabItemsClient` tests in Task 2, which mock `api.deleteVocabItem`. This task is verified by compiling.

- [ ] **Step 1: Add the client property**

In `Lengua/Core/API/APIClient.swift`, inside the `@DependencyClient struct APIClient`, after the `saveVocabItem` declaration:

```swift
  /// Permanently deletes one of the signed-in user's vocab items (auth required).
  /// The server returns 204 on delete and 404 when the item is already gone or
  /// owned by someone else; both mean "no longer exists", so both resolve without
  /// error.
  var deleteVocabItem: @Sendable (_ id: String) async throws -> Void
```

- [ ] **Step 2: Add the live implementation**

In `Lengua/Core/API/APIClient+Live.swift`, add a new closure to the `APIClient(...)` initializer after `saveVocabItem` (add a comma after the `saveVocabItem` closure's closing `}`):

```swift
      deleteVocabItem: { id in
        @Shared(.auth) var auth
        guard let token = auth.jwtToken, !token.isEmpty else {
          throw APIError.unauthorized
        }

        let url = baseUrl
          .appendingPathComponent("v1/vocab-items")
          .appendingPathComponent(id)
        let response = await session.request(
          url,
          method: .delete,
          headers: [.authorization(bearerToken: token)]
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw response.error ?? APIError.dataNotValid
        }

        // 204 = deleted, 404 = already gone or not owned. Both are the same end
        // state for the client, so treat 404 as success (mirrors save's 200/201).
        if httpResponse.statusCode == 204 || httpResponse.statusCode == 404 {
          return
        }
        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        throw APIError.dataNotValid
      }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `make format && make lint`
Expected: no errors. (Full build/tests run in Task 2's cycle.)

- [ ] **Step 4: Commit**

```bash
git add Lengua/Core/API/APIClient.swift Lengua/Core/API/APIClient+Live.swift
git commit -m "feat: add deleteVocabItem to APIClient"
```

---

## Task 2: `VocabItemsClient.delete`

**Files:**
- Modify: `Lengua/Core/VocabItems/VocabItemsClient.swift`
- Test: `LenguaTests/VocabItemsClientTests.swift`

**Interfaces:**
- Consumes: `api.deleteVocabItem(_ id: String)` from Task 1.
- Produces: `var delete: @Sendable (_ id: String) async throws -> Void` on `VocabItemsClient`. On success removes the item from `@Shared(.vocabItems)`; re-throws on failure; only mutates shared state if the account token is unchanged.

- [ ] **Step 1: Write the failing tests**

In `LenguaTests/VocabItemsClientTests.swift`, add these tests inside the `VocabItemsClientTests` struct (the `item(id:familiarity:)` helper already exists):

```swift
  @Test func deleteRemovesItemFromSharedStateOnSuccess() async throws {
    try await withDependencies {
      $0.api.deleteVocabItem = { _ in }  // 204 success
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(
        items: [item(id: "1"), item(id: "2")])
      @Dependency(\.vocabItemsClient) var client

      try await client.delete("1")

      expectNoDifference(vocabItems.items.map(\.id), ["2"])
    }
  }

  @Test func deleteTreats404AsSuccess() async throws {
    // The live APIClient maps 404 to a normal return, so from the client's
    // perspective a 404 is indistinguishable from a 204: the item is removed.
    try await withDependencies {
      $0.api.deleteVocabItem = { _ in }  // stands in for 204 or 404
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "gone")])
      @Dependency(\.vocabItemsClient) var client

      try await client.delete("gone")

      expectNoDifference(vocabItems.items.isEmpty, true)
    }
  }

  @Test func deleteThrowsAndKeepsItemOnFailure() async {
    await withDependencies {
      $0.api.deleteVocabItem = { _ in throw APIError.dataNotValid }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      @Dependency(\.vocabItemsClient) var client

      await #expect(throws: APIError.self) { try await client.delete("1") }

      expectNoDifference(vocabItems.items.map(\.id), ["1"])
    }
  }

  @Test func deleteIsNoOpWhenItemAlreadyAbsent() async throws {
    try await withDependencies {
      $0.api.deleteVocabItem = { _ in }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "t")
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "keep")])
      @Dependency(\.vocabItemsClient) var client

      try await client.delete("not-there")  // must not trap

      expectNoDifference(vocabItems.items.map(\.id), ["keep"])
    }
  }

  @Test func deleteDiscardsRemovalIfAccountChangedMidDelete() async throws {
    try await withDependencies {
      $0.api.deleteVocabItem = { _ in
        @Shared(.auth) var auth
        $auth.withLock { $0 = Auth(jwtToken: "userB") }  // account switches mid-delete
      }
      $0.vocabItemsClient = .liveValue
    } operation: {
      @Shared(.auth) var auth = Auth(jwtToken: "userA")
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      @Dependency(\.vocabItemsClient) var client

      try await client.delete("1")

      // userA's delete must not mutate userB's shared library.
      expectNoDifference(vocabItems.items.map(\.id), ["1"])
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL — `value of type 'VocabItemsClient' has no member 'delete'`.

- [ ] **Step 3: Add the `delete` property and live implementation**

In `Lengua/Core/VocabItems/VocabItemsClient.swift`, add to the `@DependencyClient struct VocabItemsClient`, after `clear`:

```swift
  /// Deletes one vocab item server-side, then removes it from
  /// `@Shared(.vocabItems)` on success. Throws on failure without mutating
  /// shared state. Bound to the current account: a sign-out or account switch
  /// mid-delete discards the local removal.
  var delete: @Sendable (_ id: String) async throws -> Void
```

Then add the live implementation to the `VocabItemsClient(...)` initializer, after the `clear` closure (add a comma after `clear`'s closing `}`):

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: PASS (all five delete tests + existing suite).

- [ ] **Step 5: Format, lint, commit**

```bash
make format && make lint
git add Lengua/Core/VocabItems/VocabItemsClient.swift LenguaTests/VocabItemsClientTests.swift
git commit -m "feat: add delete to VocabItemsClient"
```

---

## Task 3: `LenguaAlert.deleteFailed`

**Files:**
- Modify: `Lengua/Views/Reusable Components/LenguaAlert.swift`

**Interfaces:**
- Produces: `static var deleteFailed: LenguaAlert` used by Task 4.

Verified by compiling (consumed in Task 4's tests). This is a trivial addition folded here so Task 4 has the symbol available.

- [ ] **Step 1: Add the alert**

In `Lengua/Views/Reusable Components/LenguaAlert.swift`, inside the `extension LenguaAlert`, after `saveFailed`:

```swift
  static var deleteFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Delete",
      message: "We couldn't delete that word just now. Check your connection and try again.")
  }
```

- [ ] **Step 2: Commit** (build happens in Task 4)

```bash
git add "Lengua/Views/Reusable Components/LenguaAlert.swift"
git commit -m "feat: add deleteFailed alert"
```

---

## Task 4: `LibraryPageModel` delete state + action

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (model only)
- Test: `LenguaTests/LibraryPageModelTests.swift`

**Interfaces:**
- Consumes: `vocabItemsClient.delete(_ id: String)` from Task 2; `LenguaAlert.deleteFailed` from Task 3.
- Produces on `LibraryPageModel`: `var presentedAlert: LenguaAlert?`, `var deletingItemIds: Set<VocabItem.ID>`, `func deleteButtonTapped(_ item: VocabItem) async`, `func isDeleting(_ id: VocabItem.ID) -> Bool`, `var deleteButtonTitle: String`.

- [ ] **Step 1: Write the failing tests**

In `LenguaTests/LibraryPageModelTests.swift`, add inside the `LibraryPageModelTests` struct (the `item(...)` helper already exists):

```swift
  @Test func deleteButtonTappedRemovesItem() async {
    let deleted = LockIsolated<[String]>([])
    let model = withDependencies {
      $0.vocabItemsClient.delete = { id in
        deleted.withValue { $0.append(id) }
        @Shared(.vocabItems) var vocabItems
        $vocabItems.withLock { _ = $0.items.remove(id: id) }
      }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(
        items: [item(id: "1"), item(id: "2")])
      return LibraryPageModel()
    }

    await model.deleteButtonTapped(item(id: "1"))

    expectNoDifference(deleted.value, ["1"])
    expectNoDifference(model.sortedItems.map(\.id), ["2"])
    expectNoDifference(model.presentedAlert, nil)
  }

  @Test func deleteFailureShowsAlertAndKeepsItem() async {
    let model = withDependencies {
      $0.vocabItemsClient.delete = { _ in throw APIError.dataNotValid }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      return LibraryPageModel()
    }

    await model.deleteButtonTapped(item(id: "1"))

    expectNoDifference(model.presentedAlert, .deleteFailed)
    expectNoDifference(model.sortedItems.map(\.id), ["1"])
    expectNoDifference(model.isDeleting("1"), false)
  }

  @Test func deleteButtonTappedIsGuardedAgainstDuplicateTaps() async {
    let callCount = LockIsolated(0)
    let release = AsyncStream.makeStream(of: Void.self)
    let model = withDependencies {
      $0.vocabItemsClient.delete = { _ in
        callCount.withValue { $0 += 1 }
        var iterator = release.stream.makeAsyncIterator()
        _ = await iterator.next()  // hold the first delete in flight
      }
    } operation: {
      @Shared(.vocabItems) var vocabItems = VocabItems(items: [item(id: "1")])
      return LibraryPageModel()
    }

    async let first: Void = model.deleteButtonTapped(item(id: "1"))
    // Yield so `first` runs far enough to insert the id and suspend on `release`.
    await Task.yield()
    expectNoDifference(model.isDeleting("1"), true)

    await model.deleteButtonTapped(item(id: "1"))  // second tap: guarded no-op
    expectNoDifference(callCount.value, 1)

    release.continuation.yield()
    await first
    expectNoDifference(model.isDeleting("1"), false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL — `LibraryPageModel` has no member `deleteButtonTapped` / `isDeleting` / `presentedAlert`.

- [ ] **Step 3: Add model state, action, and view helpers**

In `Lengua/Views/Pages/LibraryPage.swift`, in `LibraryPageModel`:

Under `// MARK: - Properties`, after `var sortMode`:

```swift
  var presentedAlert: LenguaAlert?
  var deletingItemIds: Set<VocabItem.ID> = []
```

Under `// MARK: - User Actions`, after `retryButtonTapped`:

```swift
  func deleteButtonTapped(_ item: VocabItem) async {
    guard !deletingItemIds.contains(item.id) else { return }
    deletingItemIds.insert(item.id)
    defer { deletingItemIds.remove(item.id) }
    do {
      try await vocabItemsClient.delete(item.id)
    } catch {
      presentedAlert = .deleteFailed
    }
  }
```

Under `// MARK: - View Helpers`, add:

```swift
  var deleteButtonTitle: String { "Delete" }

  func isDeleting(_ id: VocabItem.ID) -> Bool { deletingItemIds.contains(id) }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
make format && make lint
git add Lengua/Views/Pages/LibraryPage.swift LenguaTests/LibraryPageModelTests.swift
git commit -m "feat: add delete action to LibraryPageModel"
```

---

## Task 5: `LibraryPage` view — List + swipe-to-delete

**Files:**
- Modify: `Lengua/Views/Pages/LibraryPage.swift` (view only)

**Interfaces:**
- Consumes: `model.sortedItems`, `model.deleteButtonTapped(_:)`, `model.isDeleting(_:)`, `model.deleteButtonTitle`, `model.presentedAlert` from Task 4.

This is a SwiftUI view change with no unit test; verified by building and running the app (Step 3). Follow `pfw-modern-swiftui` for binding/List idioms.

- [ ] **Step 1: Convert the item list to a `List` and wire the alert**

In `Lengua/Views/Pages/LibraryPage.swift`, replace the `else` branch of `content` (the `ScrollView { LazyVStack { ForEach ... } }` block) with:

```swift
    } else {
      List {
        ForEach(model.sortedItems) { item in
          LibraryRow(
            targetText: item.targetText,
            sourceText: item.sourceText,
            deepBlue: deepBlue,
            cardColor: cardColor
          )
          .overlay {
            if model.isDeleting(item.id) {
              ProgressView()
                .tint(deepBlue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardColor.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)
            }
          }
          .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
              Task { await model.deleteButtonTapped(item) }
            } label: {
              Label(model.deleteButtonTitle, systemImage: "trash")
            }
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .environment(\.defaultMinListRowHeight, 0)
    }
```

Then attach the alert on the page. On the outermost `ZStack` in `body` (after its `.frame`/closing brace of the `ZStack` content, at the `ZStack` modifier level), add:

```swift
    .lenguaAlert($model.presentedAlert)
```

- [ ] **Step 2: Format, lint**

Run: `make format && make lint`
Expected: no errors.

- [ ] **Step 3: Build and visually verify**

Run the app (Library tab with at least one saved item) and confirm:
- Cards look the same as before (rounded, cream background, 10pt vertical gap, 16pt horizontal page padding preserved by the surrounding `VStack`'s `.padding(.horizontal, 16)`).
- No default `List` separators or grey background show through (blue page background is visible between cards).
- Swiping a row from the trailing edge reveals a red **Delete** button; a full swipe does NOT auto-delete.
- Tapping **Delete** shows a spinner over the row until it disappears; deleting the last item returns to the empty state.

If card spacing/padding regressed, adjust `.listRowInsets` (and confirm the `VStack`'s existing horizontal padding still wraps the `List`). Do not remove the `.scrollContentBackground(.hidden)` — it is what lets the blue page background show.

- [ ] **Step 4: Commit**

```bash
git add Lengua/Views/Pages/LibraryPage.swift
git commit -m "feat: swipe-to-delete on Library page"
```

---

## Self-review notes

- **Spec coverage:** APIClient delete (Task 1), client delete + account guard + 404-as-success + no-op-absent + throws-keeps (Task 2), alert (Task 3), model state/action/guard/alert (Task 4), List conversion + swipe + spinner + alert wiring + `allowsFullSwipe:false` (Task 5). All spec test cases mapped. The two live-layer-only cases from the spec (401 mapping, 204 no-body) are handled in Task 1's implementation and covered by compiling + the client tests that mock the api; they are not separately unit-tested because the live Alamofire layer has no existing unit-test harness (consistent with `getVocabItems`/`saveVocabItem`, which also have none).
- **Type consistency:** `deleteVocabItem(_ id: String)` (API) → `delete(_ id: String)` (client) → `deleteButtonTapped(_ item: VocabItem)` / `isDeleting(_ id: VocabItem.ID)` (model). `VocabItem.ID == String`. `presentedAlert: LenguaAlert?` matches `.lenguaAlert(_ alert: Binding<LenguaAlert?>)`.
- **Ordering:** Tasks are bottom-up so each task's dependencies exist when its tests run. Task 3 precedes Task 4 so `.deleteFailed` exists.
