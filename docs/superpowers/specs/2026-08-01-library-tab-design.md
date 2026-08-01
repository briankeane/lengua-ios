# Library Tab — Design

**Date:** 2026-08-01
**Status:** Approved (brainstorming), pending implementation plan

## Goal

Replace the placeholder "Deck" tab with a real "Library" tab that lists **all**
of the user's vocab items, sortable **alphabetically**, **by date**, and **by
familiarity** (0–5). Read-only for v1. Vocab items are **app-wide shared state**
that any screen can read and edit.

## Locked product decisions

1. **Vocab items are shared app-wide state.** They live in a single
   `@Shared(.vocabItems)` value that multiple screens read and (later) edit —
   not local to the Library page.
2. **Lifecycle-driven loading.** The shared vocab items are:
   - **loaded / refreshed on sign-in and on the app entering the foreground**, and
   - **cleared on sign-out**.
   The Library page does *not* trigger loads on appear; it only displays the
   shared state (plus a manual retry on error).
3. **In-memory, not persisted.** The server is the source of truth and the data
   is refreshed on sign-in/foreground and cleared on sign-out, so the shared
   value is an in-memory key (like `.activeTab`), not a file-backed offline
   cache. Upgrading to file storage later is a localized change.
4. **Load all, sort client-side.** A load pages through the endpoint following
   `nextCursor` until `null`, holds every item in memory, and sorts locally. No
   infinite scroll.
5. **No language filter (yet).** Keep `targetLanguageCode` plumbed as an
   optional parameter but pass `nil`. A "current target language" may come later.
6. **Row layout:** `targetText` primary, `sourceText` secondary, familiarity
   (0–5) as filled/empty **dots** trailing. Read-only — no tap, no detail view.
7. **Sort modes:** Alphabetical, Date, Familiarity.

## Server endpoint

`GET /v1/vocab-items` — returns only the caller's own items.

- **Auth:** `Authorization: Bearer <accessToken>`.
- **Query params (all optional):** `targetLanguageCode` (string, case-insensitive
  exact), `limit` (int, default 50, range 1–100, `>100` → 400), `cursor` (opaque
  base64 keyset token — never construct or parse it).
- **Ordering:** newest first (`createdAt` desc, `id` tiebreak).
- **200 body:** `{ "vocabItems": [ … ], "pagination": { "limit": 50, "nextCursor": "<opaque>" | null } }`.
- `nextCursor == null` means end of list. No total count.
- Timestamps are ISO8601 **with fractional milliseconds** and `Z`
  (`2026-08-01T10:00:00.000Z`).
- `lastSeenAt`, `nextDueAt`, `lastOutcome` nullable → optionals; `familiarity`,
  `timesSeen`, `timesCorrect`, `timesIncorrect` non-null ints; `lastOutcome` a
  free-form nullable `String?`.

## Components

### 1. `VocabItem` model — `Lengua/Models/VocabItem.swift`

`struct VocabItem: Codable, Equatable, Sendable, Identifiable` with every field
from the contract; nullable fields as optionals; timestamps as `Date`/`Date?`.
No `CodingKeys` (1:1 camelCase mapping, per repo convention).

### 2. Date decoding — `Lengua/Extensions/JSONDecoder+Lengua.swift`

`JSONDecoder.lenguaISO8601`: a decoder whose `dateDecodingStrategy` tries
`ISO8601DateFormatter` with `.withFractionalSeconds` first, then plain
`.withInternetDateTime`, throwing `DecodingError.dataCorrupted` otherwise. Scoped
to vocab decoding; the bare `JSONDecoder()` elsewhere is untouched.

### 3. APIClient — thin single-page transport

`APIClient.getVocabItems: @Sendable (_ targetLanguageCode: String?, _ limit: Int?, _ cursor: String?) async throws -> VocabItemsPage`,
where `struct VocabItemsPage: Equatable, Sendable { var items: [VocabItem]; var nextCursor: String? }`.
The client returns one page; the load-all loop lives in `VocabItemsClient`. Live
impl builds query params via Alamofire `URLEncoding`, attaches
`Authorization: Bearer` from `@Shared(.auth)`, decodes with `lenguaISO8601`, and
throws `APIError` on non-2xx / missing token.

### 4. Shared vocab state

`Lengua/State/VocabItems.swift`:

```swift
struct VocabItems: Equatable, Sendable {
  var items: IdentifiedArrayOf<VocabItem> = []
  var isLoading = false
  var loadFailed = false
}
```

`Lengua/State/SharedUserDefaults.swift` gains an **in-memory** key:

```swift
extension SharedKey where Self == InMemoryKey<VocabItems>.Default {
  static var vocabItems: Self {
    Self[.inMemory("vocabItems"), default: VocabItems()]
  }
}
```

### 5. `VocabItemsClient` dependency — `Lengua/Core/VocabItems/VocabItemsClient.swift`

The single home for the load-all loop, reused by the app lifecycle and the
Library retry button.

```swift
@DependencyClient
struct VocabItemsClient: Sendable {
  var refresh: @Sendable () async -> Void
  var clear: @Sendable () -> Void
}
```

Live behavior:
- **`refresh`** — coalesced via an atomic compare-and-set on `isLoading` inside a
  single `$vocabItems.withLock` (returns early if a load is already running, so
  overlapping sign-in + foreground triggers load once). Then pages through
  `api.getVocabItems(nil, 100, cursor)` until `nextCursor == nil`. Before
  committing results it re-checks `@Shared(.auth).isLoggedIn`, so a sign-out
  mid-load cannot repopulate. On success writes `items`, clears `isLoading`. On
  `CancellationError` clears `isLoading` without setting `loadFailed`. On other
  errors sets `loadFailed`, clears `isLoading`.
- **`clear`** — `$vocabItems.withLock { $0 = VocabItems() }`.

Reads `@Dependency(\.api)` and `@Shared(...)` inside the closures (resolved at
call time, so test overrides apply).

### 6. `ContentViewModel` — app lifecycle (in `Lengua/Views/Pages/ContentView.swift`)

`ContentView` is currently model-less; add a model that owns auth gating and the
vocab lifecycle.

```swift
@MainActor @Observable final class ContentViewModel: ViewModel {
  @ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient
  @ObservationIgnored @Shared(.auth) var auth

  var isLoggedIn: Bool { auth.isLoggedIn }

  func authStateChanged() async {
    if auth.isLoggedIn { await vocabItemsClient.refresh() }
    else { vocabItemsClient.clear() }
  }

  func appEnteredForeground() async {
    guard auth.isLoggedIn else { return }
    await vocabItemsClient.refresh()
  }
}
```

`ContentView` uses `model.isLoggedIn` for the MainContainer/SignInPage gate and
wires:
- `.task(id: model.isLoggedIn) { await model.authStateChanged() }` — covers fresh
  sign-in, cold launch already-signed-in, and sign-out (clear).
- `.onChange(of: scenePhase)` → `.active` ⇒ `Task { await model.appEnteredForeground() }`.

The coalescing lives in the shared `isLoading` flag, so recreating the model
(SwiftUI re-init) is harmless.

### 7. `LibraryPageModel` (renames `DeckPageModel`)

`@MainActor @Observable`, reads the shared state — it does **not** own or trigger
loads.

- `@ObservationIgnored @Dependency(\.vocabItemsClient) var vocabItemsClient`
- `@ObservationIgnored @Shared(.vocabItems) var vocabItems`
- `var sortMode: SortMode = .date`
- Derived: `sortedItems` (sorts `vocabItems.items`), `isLoading`
  (`vocabItems.isLoading`), `isEmptyStateVisible`
  (`!isLoading && !loadFailed && items.isEmpty`), `showsRetry`
  (`loadFailed && items.isEmpty`).
- `func retryButtonTapped() async { await vocabItemsClient.refresh() }`
- All display strings + familiarity dot helpers live here (title "Library", empty
  state, sort labels, `familiarityLevel(for:)`, `familiarityMaxLevel = 5`).

### 8. Sort modes (`sortedItems`)

- **Date** — `createdAt` desc (default on open). Tie-break `id`.
- **Alphabetical** — `targetText` via `localizedCaseInsensitiveCompare`, tie-break
  `sourceText`, then `id`.
- **Familiarity** — ascending (least-known first), tie-break `createdAt` desc.

### 9. `LibraryPage` view

`List` of rows (target primary / source secondary / familiarity dots trailing),
sort control (`Menu`/`Picker`) in the toolbar bound to `model.sortMode`, and
loading / empty / retry overlays driven by the model. Reflects shared-state
changes automatically via `@Shared` observation. No load-on-appear. Zero logic,
zero hardcoded strings.

### 10. Tab wiring — `Lengua/Views/Pages/MainContainer.swift`

Rename `ActiveTab` case `deck` → `library`; `libraryTabTitle` = "Library";
`libraryTabIconName` = `"books.vertical"`; update the `TabView` block. `activeTab`
is in-memory, default `.lookUp` — no migration cost.

## Error handling

- Missing token → `getVocabItems` throws; surfaces as `loadFailed`.
- Network / decode / non-2xx → `loadFailed`; Library shows a retry affordance that
  calls `vocabItemsClient.refresh()`.
- `CancellationError` → swallowed (no `loadFailed`).
- Sign-out during a load → results discarded (auth re-check before commit).

## Testing

All tests use **swift-testing** (`@Suite`/`@Test`, `@MainActor`,
`expectNoDifference`/`expectDifference`). Suites touching `@Shared` in-memory
state are `.serialized`. The existing XCTest `DeckPageModelTests` and
`MainContainerModelTests` are converted to swift-testing.

- **VocabItem decoding:** fractional / non-fractional / null / unparseable dates.
- **API:** injected-dependency override; envelope decode.
- **VocabItemsClient:** loads all pages into shared state; error → `loadFailed`;
  `CancellationError` → no `loadFailed`; coalescing (concurrent refresh loads
  once); `clear` resets; sign-out mid-load discards results.
- **ContentViewModel:** logged-in `authStateChanged` refreshes, logged-out clears;
  `appEnteredForeground` refreshes only when logged in.
- **LibraryPageModel:** three sorts (read shared), derived `isLoading` / empty /
  retry, `retryButtonTapped` calls `refresh`, title.
- **MainContainer:** `ActiveTab.allCases` contains `.library`; title/icon strings.

## Out of scope (v1)

- Language filter / current-language concept.
- Editing vocab items from the Library (shared state supports it; no UI yet).
- Row tap / detail view, search, server-side sorting, infinite scroll.
- File-backed / offline persistence of the shared state.
