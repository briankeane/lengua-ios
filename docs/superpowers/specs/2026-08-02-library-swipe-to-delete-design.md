# Library swipe-to-delete — design

## Goal

Let a user delete a saved vocab item from the Library page by swiping the row
and tapping a red **Delete** button. The delete is permanent server-side.

## Product decisions (locked)

- **No confirmation dialog.** Swipe reveals a Delete button; tapping it starts
  the delete. `allowsFullSwipe: false` — a full swipe does *not* auto-delete
  (avoids animating the row off-screen and snapping it back with a spinner under
  the wait-for-server model).
- **Wait-for-server, not optimistic.** The row stays visible with a per-row
  spinner while the `DELETE` is in flight, and only disappears once the server
  confirms. On failure the row stays and an alert is shown.
- **Convert the page to a styled `List`.** `.swipeActions` requires a `List`;
  the current page is `ScrollView` + `LazyVStack`. The card look is preserved
  via list-row modifiers.

## Server contract (already implemented on `briankeane/delete-vocab-endpoint`)

`DELETE /v1/vocab-items/{vocabItemId}`, Bearer auth.

- `204` — deleted, no body.
- `404` — no item with that id owned by the user (already gone, or someone
  else's). Treated as **success** on the client: same end state.
- `401` — unauthenticated.
- `400` — malformed id (not a UUID).

This is iOS-only work; it assumes the server branch ships.

## Components

### 1. `APIClient.deleteVocabItem`

```swift
var deleteVocabItem: @Sendable (_ id: String) async throws -> Void
```

Live: `DELETE base/v1/vocab-items/{id}` with the bearer token. Build the URL
with `appendingPathComponent(id)` (path-safe; never string-interpolate the id).
No response body is decoded.

- `204` or `404` → return normally (idempotent; mirrors `saveVocabItem`
  treating 200/201 identically).
- `401` → throw `APIError.unauthorized`.
- anything else / transport error → throw `APIError.dataNotValid`.

### 2. `VocabItemsClient.delete`

```swift
var delete: @Sendable (_ id: String) async throws -> Void
```

Live:
1. Capture `auth.jwtToken` (the starting token).
2. `try await api.deleteVocabItem(id)`.
3. On success, **only if `auth.jwtToken == startingToken`**, remove the item
   from `@Shared(.vocabItems)`:
   `$vocabItems.withLock { _ = $0.items.remove(id: id) }`.
4. On failure, re-throw without mutating shared state.

The account-token guard mirrors `refresh`: a sign-out or account switch during
an in-flight delete must not mutate the current account's shared library.
`delete` never touches `isLoading` or `loadFailed` (a delete failure is not a
library-load failure). Removing an id that is already absent is a harmless
no-op.

### 3. `LibraryPageModel`

```swift
// Properties
var presentedAlert: LenguaAlert?
var deletingItemIds: Set<VocabItem.ID> = []

// User Actions
func deleteButtonTapped(_ item: VocabItem) async {
  guard !deletingItemIds.contains(item.id) else { return }
  deletingItemIds.insert(item.id)
  defer { deletingItemIds.remove(item.id) }
  do { try await vocabItemsClient.delete(item.id) }
  catch { presentedAlert = .deleteFailed }
}

// View Helpers
func isDeleting(_ id: VocabItem.ID) -> Bool { deletingItemIds.contains(id) }
var deleteButtonTitle: String { "Delete" }
```

Add `@Dependency(\.vocabItemsClient)` is already present. Add
`LenguaAlert.deleteFailed`. A `401` folds into the generic "couldn't delete"
alert, matching how `refresh` treats auth errors generically — no separate
re-auth path in this tab.

### 4. `LibraryPage` view

Convert the item list from `ScrollView { LazyVStack { ForEach ... } }` to:

```swift
List {
  ForEach(model.sortedItems) { item in
    LibraryRow(...)
      .overlay { if model.isDeleting(item.id) { ProgressView().allowsHitTesting(false) } }
      .listRowInsets(...)          // re-apply old horizontal padding + spacing
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          Task { await model.deleteButtonTapped(item) }
        } label: { Label(model.deleteButtonTitle, systemImage: "trash") }
      }
  }
}
.listStyle(.plain)
.scrollContentBackground(.hidden)
```

Wire `.lenguaAlert($model.presentedAlert)` on the page. Preserve the existing
card styling (rounded card, colors, spacing) — the riskiest part, since list-row
defaults (margins, separators, background) differ from the old stack. Build and
visually verify the cards look unchanged.

## Testing

`LenguaAlert.deleteFailed`: title "Couldn't Delete", connection-style message
matching the voice of `saveFailed`.

### `VocabItemsClientTests`
- `deleteRemovesItemFromSharedStateOnSuccess` — 204 path removes the id.
- `deleteTreats404AsSuccess` — api returns normally for 404; item removed.
- `deleteThrowsAndKeepsItemOnFailure` — api throws; item stays; re-throws.
- `deleteIsNoOpWhenItemAlreadyAbsent` — removing a missing id does not trap.
- `deleteDiscardsRemovalIfAccountChangedMidDelete` — token changes during the
  api call; shared library is not mutated.

### `LibraryPageModelTests`
- `deleteButtonTappedRemovesItem` — client mock removes; `sortedItems` no longer
  contains it.
- `deleteFailureShowsAlert` — client throws; `presentedAlert == .deleteFailed`.
- `deleteButtonTappedIsGuardedAgainstDuplicateTaps` — a second call while the
  first is in flight does not invoke the client twice.
- `deletingItemIdsClearedAfterSuccessAndFailure` — set is empty once the call
  returns, both paths.

All model/client tests follow the existing pattern: `@MainActor`,
`@Suite(.serialized)`, local `@Shared` state, `withDependencies` overrides,
`expectNoDifference`. The `List` styling is view-only and verified by building
and running the app, not by unit tests.

## Out of scope

- Undo / restore after delete.
- Bulk / multi-select delete.
- A dedicated 401 re-auth flow from the Library tab.
