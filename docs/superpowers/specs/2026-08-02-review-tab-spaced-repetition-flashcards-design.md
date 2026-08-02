# Review Tab — Spaced-Repetition Flashcards (iOS)

**Date:** 2026-08-02
**Status:** Design approved; ready for implementation plan
**Related:** server-side dual-track SRS endpoints (see `.context/server-srs-prompt.md`,
built in a parallel context)

## Goal

Turn the placeholder Review tab into a spaced-repetition flashcard experience over the
user's saved vocab items. Each vocab item is reviewed on **two independent SRS tracks**:

- **receptive** (recognition) — see the target word, recall the meaning → **flip** card,
  self-graded.
- **productive** (production) — see the meaning, produce the target word → **type** card,
  auto-graded. (Voice is a future productive modality; out of scope here.)

The server owns all scheduling (Leitner boxes, per track). The client fetches what's due,
presents it, and reports each outcome.

## Server contract (already specced, built in parallel)

The app depends on these endpoints. Shapes are the source of truth for the client models.

- `GET /v1/vocab-items/review?direction={receptive|productive|any}&limit=&targetLanguageCode=`
  → `{ reviewCards: [{ vocabItemId, direction, sourceText, targetText,
  targetLanguageCode, familiarity, nextDueAt }], dueCounts: { receptive, productive,
  total } }`. Most-overdue first; a card due in both tracks (with `any`) appears twice.
- `POST /v1/vocab-items/:vocabItemId/review` body `{ direction, outcome }`
  (`outcome ∈ {correct, incorrect}`) → the full updated vocab item.
- `GET`/`POST /v1/vocab-items` now return the **nested** track shape (below).

## Data model changes (`Lengua/Models`, `Lengua/Core/API`)

### `VocabItem` — nested tracks (breaking change)

Replace the seven flat SRS fields (`familiarity`, `lastSeenAt`, `timesSeen`,
`timesCorrect`, `timesIncorrect`, `lastOutcome`, `nextDueAt`) with two nested tracks:

```swift
struct SRSTrack: Codable, Equatable, Sendable {
  let familiarity: Int
  let nextDueAt: Date?
  let lastSeenAt: Date?
  let timesSeen: Int
  let timesCorrect: Int
  let timesIncorrect: Int
  let lastOutcome: String?
}
// VocabItem gains: let receptive: SRSTrack; let productive: SRSTrack
// (drops the seven flat fields)
```

### New review types

```swift
enum ReviewDirection: String, Codable, Sendable { case receptive, productive }
enum ReviewOutcome: String, Codable, Sendable { case correct, incorrect }

struct ReviewCard: Equatable, Sendable, Identifiable {
  let vocabItemId: String
  let direction: ReviewDirection
  let sourceText: String        // the meaning
  let targetText: String        // the foreign word (the answer for productive)
  let targetLanguageCode: String
  let familiarity: Int
  let nextDueAt: Date?
  // Identity is (vocabItemId, direction): a card can appear on both tracks.
  var id: String { "\(vocabItemId)#\(direction.rawValue)" }
}

struct DueCounts: Equatable, Sendable { let receptive, productive, total: Int }
struct ReviewQueue: Equatable, Sendable { let cards: [ReviewCard]; let dueCounts: DueCounts }
```

### `APIClient` additions

```swift
var getReviewQueue: @Sendable (_ direction: ReviewDirection?, _ limit: Int?,
  _ targetLanguageCode: String?) async throws -> ReviewQueue   // nil direction ⇒ "any"
var submitReview: @Sendable (_ vocabItemId: String, _ direction: ReviewDirection,
  _ outcome: ReviewOutcome) async throws -> VocabItem
```

Live impl mirrors existing methods (`APIClient+Live.swift`, `JSONDecoder.lenguaISO8601`,
bearer auth, `APIError` mapping).

### `LibraryPage` sort touch-up

`LibraryPage`'s familiarity sort reads the now-removed flat field. Update it to sort by
the **weaker** track (`min(receptive.familiarity, productive.familiarity)`) so "least
familiar first" still means what it says.

## Screen architecture

The Review tab (a `NavigationStack` in `MainContainer`) has two models, split so each has
one job and is independently testable:

- **`ReviewPageModel` / `ReviewPage`** — the **start / hub** screen.
- **`ReviewSessionModel` / `ReviewSessionView`** — one **review session**, presented over
  the hub via `.fullScreenCover` while `reviewPageModel.session != nil`.

### `ReviewPageModel` (start / hub)

- **Dependencies:** `@Dependency(\.api)`. **Shared:** `@Shared(.auth)` (auth-gated).
- On `viewAppeared()` / after a session ends: `await refreshDueCounts()` →
  `api.getReviewQueue(nil, 1, nil)` and read `dueCounts`, discarding the one card.
  Always pass `direction = nil` (any) here so the hub shows **both** track counts
  regardless of the selected mode. (`dueCounts` are per-track user totals, independent of
  `limit` and of the `direction` filter — confirm this holds when wiring against the real
  endpoint.)
- **Mode:** `enum ReviewMode { case adaptive, recognition, production }`, default
  `.adaptive`. Maps to the queue `direction` param: `.adaptive → nil (any)`,
  `.recognition → .receptive`, `.production → .productive`.
- **State surfaced to the view (all text lives in the model):** navigation title
  ("Review"); due summary string ("12 to recognize · 3 to produce", pluralized; "All
  caught up 🎉" when zero); mode-picker labels; start-button title; empty-state text that
  differs for **no words saved yet** ("Save some words to review them here.") vs **none
  due** ("You're all caught up — check back later."); loading + error/retry states
  (mirror `LibraryPage`'s retry pattern).
- **Actions:** `startReviewingButtonTapped()` fetches a batch
  (`api.getReviewQueue(direction, sessionLimit, nil)`, `sessionLimit = 20`) and, if
  non-empty, creates `session = ReviewSessionModel(cards:...)`. `sessionFinished()` clears
  `session` and refreshes due counts.

### `ReviewSessionModel` (one session)

- **Dependencies:** `@Dependency(\.api)`.
- **Init:** with the fetched `[ReviewCard]` batch. `batchCount` = distinct cards = the
  progress denominator.
- **Queue mechanics (re-queue until correct):**
  - `queue: [ReviewCard]`, `currentIndex = 0`; `current` = `queue.first`.
  - **Flip card (receptive):** `isRevealed` toggled by `revealButtonTapped()`; then
    `gotItButtonTapped()` / `missedItButtonTapped()`.
  - **Type card (productive):** `typedAnswer` binding; `submitTypedAnswerButtonTapped()`
    runs the forgiving check (below) → shows result + correct answer; user confirms, or
    uses `markCorrectOverrideButtonTapped()` on a false-negative.
  - **Grading:** every graded answer `await api.submitReview(id, direction, outcome)`
    (optimistic UI; on failure keep the card and surface a retry — do not advance).
    - **correct** → remove card from `queue`, `clearedCount += 1`.
    - **incorrect** → `queue.removeFirst()` and re-insert at `min(3, queue.count)` (≈3
      cards later, or the end if fewer remain), so it resurfaces this session and stays
      until correct; no change to `clearedCount`.
  - `progress` = `clearedCount / batchCount`; `progressText` ("3 of 15").
  - When `queue` empties → `isFinished = true` → done state ("Nice work!"), then
    `doneButtonTapped()` → parent `sessionFinished()`.
- **All display text in the model:** prompts, "Tap to reveal", button titles, the accent
  note ("Mind the accent: …"), result labels, done-screen copy.

### Forgiving typed-answer check (pure, unit-tested)

`func gradeTypedAnswer(_ typed: String, expected: String) -> TypedGrade` where
`enum TypedGrade { case correct, correctWithAccentNote, incorrect }`:

1. Normalize both: `trimmingCharacters(in: .whitespacesAndNewlines)`, collapse internal
   runs of whitespace to one space, `.lowercased()`, NFC.
2. Normalized equal → `.correct`.
3. Else strip diacritics (`folding(options: .diacriticInsensitive, locale: .current)`) on
   both; if equal → `.correctWithAccentNote`.
4. Else → `.incorrect` (the view still offers "I was right → mark correct", which submits
   `.correct`).

`.correctWithAccentNote` submits `outcome = .correct` and shows the properly-accented
`targetText`.

## Card layout (view — visuals only)

Reuse the app's blue palette / rounded-card style (as `LibraryPage`/Translate). Both card
types are a large centered card on the page-blue background:

- **Flip (receptive):** top eyebrow "Recognize"; big `targetText`; subtitle "Tap to
  reveal". Tap → reveals `sourceText` beneath a divider. Footer: **Missed it** (secondary)
  / **Got it** (prominent).
- **Type (productive):** eyebrow "Produce"; big `sourceText` prompt; a text field
  (autocapitalization off, autocorrect off, `.none` smart-quotes) + **Check** button.
  After check: show ✓/✗, the correct `targetText`, optional accent note, and either
  **Continue** or **I was right** (override) → then **Continue**.
- Top of session: a progress bar + `progressText` and a **close (✕)** to exit early
  (exiting just ends the session; already-submitted grades stand).

## Edge cases & states

- **Signed out:** Review is auth-gated; show a sign-in prompt/empty state consistent with
  the app (do not call the endpoints without a token).
- **No vocab items at all** vs **none due:** distinct hub empty-state copy.
- **Fetch error:** hub shows retry (mirror `LibraryPage`).
- **Grade submit error:** keep current card, show retry, don't advance or mutate progress.
- **Batch cleared but more due:** hub (after refresh) offers "Review more" implicitly via
  a non-zero due summary + Start.

## Testing (swift-testing, colocated, `@MainActor` structs, `.serialized` where they
touch `@Shared`)

- **`gradeTypedAnswer`** (pure): exact match; case/whitespace/NFC differences; accent-only
  → `.correctWithAccentNote`; article/synonym mismatch → `.incorrect`.
- **`ReviewSessionModel`** (mock `api` via `withDependencies`): correct removes + advances
  + bumps progress; incorrect re-queues and the card reappears and *stays until correct*;
  each grade calls `submitReview` with the right `(id, direction, outcome)`; queue-empty →
  `isFinished`; submit failure keeps the card and doesn't advance. Use
  `expectNoDifference` for value assertions.
- **`ReviewPageModel`:** due-summary strings incl. pluralization + "all caught up"; mode →
  `direction` mapping; no-items vs none-due empty states; start creates a session only when
  the batch is non-empty; auth-gating.
- **Decoding:** `VocabItem` nested-track JSON; `ReviewQueue` / `ReviewCard` JSON via
  `JSONDecoder.lenguaISO8601`.

Follow the `pfw-*` skills (dependencies, observable-models, custom-dump, testing, sharing,
modern-swiftui) per repo policy.

## Out of scope (later)

- **Voice** productive modality (speak the answer) — slots in as another productive input
  method feeding the same track.
- Multiple-choice mode; manual per-card direction override; offline persistence/retry of
  in-flight grades; configurable session size / interval tuning.
```
