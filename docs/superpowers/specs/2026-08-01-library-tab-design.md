# Library Tab — Design

**Date:** 2026-08-01
**Status:** Approved (brainstorming), pending implementation plan

## Goal

Replace the placeholder "Deck" tab with a real "Library" tab that lists **all**
of the user's vocab items, sortable **alphabetically**, **by date**, and **by
familiarity** (0–5). Read-only for v1.

## Locked product decisions

1. **Load all, sort client-side.** On open, page through the endpoint following
   `nextCursor` until it is `null`, hold every item in memory, and perform all
   sorting locally. Vocab lists are small, and the three sort modes only behave
   correctly with the full set in hand. No infinite scroll.
2. **No language filter (yet).** Keep `targetLanguageCode` plumbed through as an
   optional parameter, but pass `nil` for v1. A "current target language"
   concept may be added later.
3. **Row layout:** `targetText` primary, `sourceText` secondary, familiarity
   (0–5) rendered as filled/empty **dots** on the trailing edge. Read-only — no
   tap action, no detail view.
4. **Sort modes:** Alphabetical, Date, Familiarity.

## Server endpoint

`GET /v1/vocab-items` — returns only the caller's own items.

- **Auth:** `Authorization: Bearer <accessToken>`.
- **Query params (all optional):** `targetLanguageCode` (string, case-insensitive
  exact), `limit` (int, default 50, range 1–100, `>100` → 400), `cursor` (opaque
  base64 keyset token — never construct or parse it).
- **Ordering:** newest first (`createdAt` desc, `id` tiebreak).
- **200 body:**
  ```json
  {
    "vocabItems": [ { "id": "...", "targetLanguageCode": "es",
      "sourceText": "dog", "targetText": "perro", "familiarity": 0,
      "lastSeenAt": null, "timesSeen": 0, "timesCorrect": 0,
      "timesIncorrect": 0, "lastOutcome": null, "nextDueAt": null,
      "createdAt": "2026-08-01T10:00:00.000Z",
      "updatedAt": "2026-08-01T10:00:00.000Z" } ],
    "pagination": { "limit": 50, "nextCursor": "<opaque>" }
  }
  ```
- `nextCursor` is `null` at end of list. No total count.
- Timestamps are ISO8601 **with fractional milliseconds** and `Z`
  (`2026-08-01T10:00:00.000Z`).
- `lastSeenAt`, `nextDueAt`, `lastOutcome` are nullable → optionals.
- `familiarity`, `timesSeen`, `timesCorrect`, `timesIncorrect` are non-null ints.
- `lastOutcome` is a free-form nullable `String?` (no fixed enum — do not switch
  exhaustively).

## Components

### 1. `VocabItem` model — `Lengua/Models/VocabItem.swift`

```swift
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

No `CodingKeys` (property names map 1:1 to the camelCase JSON, matching repo
convention).

### 2. Date decoding

Swift's default `.iso8601` strategy does **not** parse the `.000Z` fractional
seconds. The live client uses a local `JSONDecoder` with a custom
`dateDecodingStrategy` that tries, in order:

1. `ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]`
2. `ISO8601DateFormatter` with `[.withInternetDateTime]` (fallback for
   timestamps without fractional seconds)

and throws `DecodingError.dataCorrupted` if neither matches. This is scoped to
the vocab-items decode path and does not change the bare `JSONDecoder()` used by
other endpoints. Optional `Date?` fields decode `null` automatically.

### 3. APIClient — thin single-page transport

`APIClient` gains one endpoint. The client returns a single page; the
"load all pages" loop lives in the model, not the client (correct seam until a
second caller needs the same behavior).

```swift
var getVocabItems: @Sendable (
  _ targetLanguageCode: String?,
  _ limit: Int?,
  _ cursor: String?
) async throws -> VocabItemsPage
```

```swift
struct VocabItemsPage: Equatable, Sendable {
  var items: [VocabItem]
  var nextCursor: String?
}
```

A real struct (not a tuple) — tuples are awkward at test call sites.

**Live implementation** (`APIClient+Live.swift`):
- Build query parameters via Alamofire `URLEncoding` (only non-nil params;
  default `limit` handled by caller passing an explicit value).
- Attach `headers: [.authorization(bearerToken: token)]`, reading the token from
  `@Shared(.auth)` inside the closure (see Auth below).
- Decode with the custom fractional-ISO8601 `JSONDecoder`.
- Throw a structured `APIError` on non-2xx responses and on a missing token.

### 4. Auth header

No request attaches a Bearer token today — this establishes the precedent. The
live client reads `@Shared(.auth)` inside its closure to get `jwtToken`.

Considered but deferred: a dedicated "current access token" `@Dependency`
(Codex's cleanest option). Reading `@Shared` directly is idiomatic for
swift-sharing, is trivially refactorable to a token dependency later, and keeps
v1 scope tight. If the token is `nil`, `getVocabItems` throws rather than making
an unauthenticated request.

### 5. `LibraryPageModel` (renames `DeckPageModel`)

`@MainActor @Observable final class LibraryPageModel: ViewModel`.

- **Dependencies:** `@ObservationIgnored @Dependency(\.api) var api`
- **State:** `items: IdentifiedArrayOf<VocabItem>`, `isLoading`, `sortMode`,
  `presentedAlert: LenguaAlert?`, `hasLoaded`
- **`viewAppeared() async`:** guarded by `hasLoaded` — set `hasLoaded`/
  `isLoading` **before the first `await`** so a tab switch or view recreation
  can't launch a duplicate full-library load. Runs the page loop:
  - request `limit: 100` (minimize round-trips)
  - append each page's items into a local array
  - stop only when `nextCursor == nil`
  - never parse the cursor
  - assign `items = IdentifiedArray(uniqueElements: loaded)` **once** at the end
  - swallow `CancellationError` (do not alert); real errors → `LenguaAlert` with
    a retry action
- **`sortedItems: [VocabItem]`** computed — applies `sortMode`.
- **Display strings** all live on the model: `navigationTitle` = "Library",
  empty-state text, error messages, sort-mode labels, and the familiarity dot
  count per row.

### 6. Sort modes

```swift
enum SortMode: String, CaseIterable, Sendable {
  case date          // default
  case alphabetical
  case familiarity
}
```

- **Date** — `createdAt` descending (default on open; matches server order and
  user expectation for a library). Tie-break `id`.
- **Alphabetical** — `targetText` via `localizedCaseInsensitiveCompare`,
  tie-break `sourceText`, then `id`.
- **Familiarity** — **ascending** (least-known first, most actionable for
  study), tie-break `createdAt` descending.

Each mode exposes a display label from the model.

### 7. `LibraryPage` view

- `List` of rows: `targetText` (primary), `sourceText` (secondary), familiarity
  dots (trailing, `familiarity` filled of 5).
- Sort control in the toolbar (`Menu`/`Picker`) bound to `model.sortMode`.
- Loading and empty states, both driven by model strings.
- Zero logic, zero hardcoded strings.

### 8. Tab wiring

- Rename `MainContainerModel.ActiveTab` case `deck` → `library`.
- `libraryTabTitle` = "Library"; `libraryTabIconName` = `"books.vertical"`.
- Update the `MainContainer` `TabView` block (page, `tabItem`, `tag`).
- `activeTab` is an in-memory `@Shared` key (not persisted), default `.lookUp` —
  renaming the case has no migration cost.

## Error handling

- Missing token → `getVocabItems` throws; model shows a `LenguaAlert`.
- Network / decode / non-2xx → `LenguaAlert` with a retry action that re-runs the
  load.
- `CancellationError` → swallowed silently.

## Testing

All tests use **swift-testing** (`@Suite` structs, `@MainActor`,
`expectNoDifference`/`expectDifference`), per repo mandate. The existing XCTest
`DeckPageModelTests` is converted to swift-testing as `LibraryPageModelTests`.

- **VocabItem decoding:** fractional-seconds timestamp, non-fractional fallback,
  `null` optional dates, full-payload round trip.
- **Load all pages:** multi-page walk assembles the full set and stops at
  `nextCursor == nil`.
- **Empty list:** no items → empty state, no error.
- **API error:** load failure sets `presentedAlert`; retry re-runs the load.
- **Duplicate-appearance guard:** calling `viewAppeared()` twice loads once.
- **Cancellation:** a cancelled load does not set an alert.
- **Sorts:** each of the three modes orders a fixed fixture as expected,
  including tie-breaks.
- **Auth-missing:** no token → error path, no unauthenticated request.
- **MainContainer:** `ActiveTab.allCases` contains `.library`; tab title/icon
  strings correct.

## Out of scope (v1)

- Language filter / current-language concept.
- Row tap / detail view.
- Search.
- Server-side sorting or infinite scroll.
- Editing, deleting, or creating vocab items.
