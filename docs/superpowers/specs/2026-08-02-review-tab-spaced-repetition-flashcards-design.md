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
  total } }`.
  - Ordering: **never-seen (null `nextDueAt`) first, then most-overdue** (`NULLS FIRST` is
    intentional — new cards surface first). When both tracks of one card are due under
    `any`, both entries appear; they get a **deterministic secondary sort by `direction`**
    so paging is stable.
  - `dueCounts` are **global per-track totals for the user, independent of `limit` and of
    the `direction` filter.** `receptive`/`productive` are per-track entry counts; `total`
    is **distinct vocab items** due in ≥1 track (so `receptive + productive ≥ total`). The
    client uses `dueCounts` only for the hub summary, and the fetched `reviewCards.count`
    (entries) for session/progress math — it never derives progress from `total`.
  - `limit` bounds **review entries** returned, not distinct cards.
  These points are pinned in the server addendum (`.context/server-srs-addendum.md`).
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
the tuple `(min(receptive.familiarity, productive.familiarity),
max(receptive.familiarity, productive.familiarity), createdAt)` so a card that's strong on
one track but weak on the other doesn't tie with a totally-unknown card. Relabel the sort
option "Weakest skill" for honesty.

### Breaking-change blast radius (enumerate before touching `VocabItem`)

Flattening → nesting `VocabItem` touches every construction/decoding site, not just
`LibraryPage`. Update all of: the `VocabItem` decoder + any fixtures; `TranslatePage`'s
save flow and anything that builds/reads a `VocabItem`; `VocabItemsClient` (de-dupe/insert
into `@Shared(.vocabItems)`); and all existing tests that construct or decode a
`VocabItem`. Grep `familiarity`, `nextDueAt`, `timesSeen`, `lastOutcome`, and
`VocabItem(` before starting.

**Release coordination:** the server response change is breaking for any already-deployed
client that decodes the flat shape. Ship the server first (or simultaneously) and confirm
there are no in-the-wild clients that will choke; if there could be, add a transitional
decoder that accepts both shapes rather than assuming an atomic cutover.

## Screen architecture

The Review tab (a `NavigationStack` in `MainContainer`) has two models, split so each has
one job and is independently testable:

- **`ReviewPageModel` / `ReviewPage`** — the **start / hub** screen.
- **`ReviewSessionModel` / `ReviewSessionView`** — one **review session**, presented over
  the hub via `.fullScreenCover(isPresented:)` driven by a `Bool` binding derived from
  `reviewPageModel.session != nil` (a full-screen takeover suits a focused flashcard flow;
  the tab has no existing modal pattern). Use the `isPresented:` overload, not
  `.fullScreenCover(item:)` — the `ViewModel` base is `Hashable`, not `Identifiable`, so
  the item overload doesn't apply without extra conformance. The two-model split is kept
  because the session logic (queue, grading, re-queue, two card types) is substantial and
  deserves isolated tests; if it turns out thin in practice, collapsing it into
  `ReviewPageModel` is a fine simplification.

### `ReviewPageModel` (start / hub)

- **Dependencies:** `@Dependency(\.api)`. **Shared:** `@Shared(.auth)` (auth-gated).
- On `viewAppeared()` / after a session ends: `await refreshDueCounts()` →
  `api.getReviewQueue(nil, 1, nil)` and read `dueCounts`, discarding the one card.
  Always pass `direction = nil` (any) here so the hub shows **both** track counts
  regardless of the selected mode. **`dueCounts` are GLOBAL per-track user totals,
  independent of `limit` AND of the `direction` filter** — this is a hard requirement on
  the server (see server addendum); the client depends on it.
- **Shared:** also read `@Shared(.vocabItems)` (already populated app-wide). The hub uses
  `vocabItems.items.isEmpty` — NOT the review queue — to tell **no words saved yet** from
  **none due right now**. The `getReviewQueue` call cannot distinguish these (an empty
  queue with `dueCounts.total == 0` says nothing about total saved words).
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

- **Dependencies:** `@Dependency(\.api)`. **Shared:** `@Shared(.vocabItems)` (to merge
  graded results back — see Grading).
- **Init:** with the fetched `[ReviewCard]` batch. **`batchCount = cards.count`** (the
  number of *review entries*, where identity is `(vocabItemId, direction)`) — a card due
  in **both** tracks counts as **two** entries and must be cleared twice. Do **not** use a
  distinct-vocab-item count as the denominator.
- **Queue mechanics (re-queue until correct):**
  - `queue: [ReviewCard]`; `current` = `queue.first`. (No `currentIndex` — it would be
    dead state; the front of the queue is the current card.)
  - **Flip card (receptive):** `isRevealed` toggled by `revealButtonTapped()`; then
    `gotItButtonTapped()` / `missedItButtonTapped()`.
  - **Type card (productive):** `typedAnswer` binding; `checkButtonTapped()` runs the
    forgiving check (below) **locally** and shows the result + correct answer. Nothing is
    submitted yet. The user then taps `continueButtonTapped()` (accepts the shown result)
    or, on a false-negative, `markCorrectOverrideButtonTapped()` (flips the pending outcome
    to `.correct`) and then Continue. **`submitReview` fires only on that final
    confirmation**, exactly once, with the confirmed outcome. Flip cards submit directly on
    Got it / Missed it.
  - **Grade submission (submit → then advance on success; not optimistic):**
    - Guard with `isSubmittingGrade`: ignore repeat taps while a submit is in flight (kills
      double-tap double-counting).
    - `await api.submitReview(id, direction, outcome)`. **On success:** merge the returned
      `VocabItem` into `@Shared(.vocabItems)` (keeps Library familiarity/sort fresh), then
      apply the queue mutation below and advance. **On failure:** keep the current card,
      stash the pending `(direction, outcome)`, and surface a retry that re-sends *that same
      outcome* (the user does not re-answer). Do not advance or mutate progress.
    - If the session was closed while a submit was in flight, ignore the response (session
      token / `isClosed` guard) — never mutate a dead session or shared state from it.
    - **correct** → remove card from `queue`, `clearedCount += 1`.
    - **incorrect** → `queue.removeFirst()`; if this card's session miss-count `< 3`,
      re-insert at index `min(3, queue.count)` (so it reappears after up to 3 other cards)
      and bump its miss-count; **once it has been missed 3× this session, drop it** (the
      server already scheduled it +10 min for a future session) so a repeatedly-missed card
      can't trap the user in an unbounded session. No change to `clearedCount`.
  - `progress` = `clearedCount / batchCount`; `progressText` ("3 of 15"). A dropped-after-3
    card still counts toward `batchCount` but is cleared from the queue, so the session
    always terminates.
  - When `queue` empties → `isFinished = true` → done state ("Nice work!"), then
    `doneButtonTapped()` → parent `sessionFinished()`.
- **All display text in the model:** prompts, "Tap to reveal", button titles, the accent
  note ("Mind the accent: …"), result labels, done-screen copy. Accepted duplicate-stats
  risk: a grade that succeeds server-side but whose response is lost, then retried, records
  the outcome twice. Acceptable for v1 (it perturbs stats/`familiarity` by one step, not
  correctness); revisit with a client attempt-id if it proves noticeable.

### Forgiving typed-answer check (pure, unit-tested)

`func gradeTypedAnswer(_ typed: String, expected: String) -> TypedGrade` where
`enum TypedGrade { case correct, correctWithAccentNote, incorrect }`:

1. Normalize both sides identically: `trimmingCharacters(in: .whitespacesAndNewlines)`,
   collapse internal whitespace runs to one space, lowercase with a **fixed** locale
   (`.lowercased(with: Locale(identifier: "en_US_POSIX"))` — never `.lowercased()` alone,
   whose behavior varies by device locale, e.g. Turkish dotless-i), then Unicode-normalize
   with `precomposedStringWithCanonicalMapping` (this is what "NFC" means in Swift; there
   is no `String.nfc()`).
2. Normalized equal → `.correct`.
3. Else compare with **vowel accents only** folded — strip acute accents and diaereses on
   vowels (á é í ó ú ü). If equal → `.correctWithAccentNote`. **`ñ` is a distinct letter,
   NOT an accent:** "ano" must never auto-pass as "año". So do **not** use a blanket
   `folding(.diacriticInsensitive)` (it collapses ñ→n); fold only the vowel-accent set.
4. Else → `.incorrect` (the view still offers "I was right → mark correct", which flips the
   pending outcome to `.correct`).

`.correctWithAccentNote` yields a pending `outcome = .correct` (submitted on Continue) and
shows the properly-accented `targetText`.

**Punctuation & articles:** the check does not strip articles or punctuation, so
`expected = "el perro"` will mark a typed `"perro"` incorrect → the user leans on the
override. That is an accepted v1 limitation; make it explicit in tests (cases: leading
article dropped, `¿…?`/`¡…!` punctuation, apostrophes) so the behavior is intentional, not
accidental. Revisit article/punctuation leniency later if the override gets heavy use.

## Card layout (view — visuals only)

Reuse the app's blue palette / rounded-card style (as `LibraryPage`/Translate). Both card
types are a large centered card on the page-blue background:

- **Flip (receptive):** top eyebrow "Recognize"; big `targetText`; subtitle "Tap to
  reveal". Tap → reveals `sourceText` beneath a divider. Footer: **Missed it** (secondary)
  / **Got it** (prominent).
- **Type (productive):** eyebrow "Produce"; big `sourceText` prompt; a text field with
  `.textInputAutocapitalization(.never)` and `.autocorrectionDisabled()` + **Check** button.
  After check: show ✓/✗, the correct `targetText`, optional accent note, and either
  **Continue** or **I was right** (override) → then **Continue**. (All these strings come
  from model properties, not view literals — see the Model responsibilities rule in
  CLAUDE.md; the labels here are illustrative.)
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
