# Review Tab — Spaced-Repetition Flashcards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the placeholder Review tab into a spaced-repetition flashcard experience over the user's saved vocab items, with independent receptive (flip) and productive (type) tracks.

**Architecture:** MV with `@Observable` models. A hub model (`ReviewPageModel`) shows due counts + mode and launches a session model (`ReviewSessionModel`) presented full-screen. The server owns Leitner scheduling per track; the client fetches what's due, presents cards, and reports outcomes. Pure typed-answer grading lives in a standalone testable function.

**Tech Stack:** Swift, SwiftUI, Point-Free `swift-dependencies` / `swift-sharing` / `swift-identified-collections`, Alamofire (live API), swift-testing + CustomDump for tests.

## Global Constraints

- **Testing:** swift-testing only (`import Testing`, `@Suite`/`@Test`, `#expect`/`#require`) — never XCTest. `@Test` names camelCase, no `test` prefix. Suites are `@MainActor` structs; mark `.serialized` when touching process-global `@Shared`. Use `expectNoDifference`/`expectDifference` (CustomDump) for value comparisons, not raw `#expect(a == b)`. Colocate tests: `Foo.swift` → `FooTests.swift`. NEVER `Task.sleep` in tests.
- **PFW skills (mandatory before writing code):** `pfw-dependencies` (any `@Dependency`/`@DependencyClient`), `pfw-observable-models` (any `*Model`), `pfw-sharing` (`@Shared`), `pfw-identified-collections` (`IdentifiedArrayOf`), `pfw-testing` + `pfw-custom-dump` (tests), `pfw-modern-swiftui` (views/bindings). Reference them per task.
- **Model owns all text/logic; View is visuals only** — no hardcoded strings in views; action methods named for the user action (`…ButtonTapped`).
- **Model MARK sections** in order: Dependencies, Shared State, Initialization, Properties, User Actions, View Helpers, Private Helpers.
- **Decoding:** always `JSONDecoder.lenguaISO8601` for server payloads.
- **All models/tests `@MainActor`.** async/await, no completion handlers.
- **Lint/format:** `make lint`, `make format-check` must pass before each commit. `make test` runs the app-hosted suite.
- **Server contract** lives in `.context/server-srs-prompt.md` + `.context/server-srs-addendum.md`; design in `docs/superpowers/specs/2026-08-02-review-tab-spaced-repetition-flashcards-design.md`. `dueCounts` are GLOBAL per-track totals independent of `limit` and `direction`.

**Server dependency:** the two review endpoints are being built in a parallel context. All tasks here are built against the contract with a mocked `api` dependency, so they can be completed and unit-tested without the live server. Full end-to-end verification (Task 7) waits for the server to land.

---

### Task 1: Data model — nested `VocabItem` tracks + review types

Breaking change: flatten → nested. Must keep the whole project compiling and all existing tests green in the same commit.

**Files:**
- Modify: `Lengua/Models/VocabItem.swift`
- Create: `Lengua/Models/Review.swift`
- Modify: `LenguaTests/VocabItem+TestSupport.swift`
- Modify: `Lengua/Views/Pages/LibraryPage.swift:54-75` (familiarity sort)
- Modify test fixtures that use the full memberwise init: `LenguaTests/LibraryPageModelTests.swift` (the `make` helper ~line 14), `LenguaTests/APIClientTests.swift:54`, `LenguaTests/VocabItemsClientTests.swift:15`, and any `TranslatePageModelTests` sites that pass `familiarity:` (the 4-arg convenience-init sites are unaffected)
- Create: `LenguaTests/ReviewModelsTests.swift`

**Interfaces:**
- Produces: `struct SRSTrack: Codable, Equatable, Sendable { let familiarity: Int; let nextDueAt: Date?; let lastSeenAt: Date?; let timesSeen: Int; let timesCorrect: Int; let timesIncorrect: Int; let lastOutcome: String? }`
- Produces: `VocabItem` with `let receptive: SRSTrack` and `let productive: SRSTrack` replacing the seven flat SRS fields (keeps `id, targetLanguageCode, sourceText, targetText, createdAt, updatedAt`).
- Produces: `enum ReviewDirection: String, Codable, Sendable { case receptive, productive }`, `enum ReviewOutcome: String, Codable, Sendable { case correct, incorrect }`, `struct ReviewCard: Equatable, Sendable, Identifiable { let vocabItemId, sourceText, targetText, targetLanguageCode: String; let direction: ReviewDirection; let familiarity: Int; let nextDueAt: Date?; var id: String { "\(vocabItemId)#\(direction.rawValue)" } }`, `struct DueCounts: Codable, Equatable, Sendable { let receptive, productive, total: Int }`, `struct ReviewQueue: Equatable, Sendable { let cards: [ReviewCard]; let dueCounts: DueCounts }`.

- [ ] **Step 1: Write the failing decoding test** in `LenguaTests/ReviewModelsTests.swift`

```swift
import Foundation
import Testing
import CustomDump
@testable import Lengua

@MainActor
@Suite struct ReviewModelsTests {
  @Test func decodesNestedVocabItemTracks() throws {
    let json = """
    { "id": "v1", "targetLanguageCode": "es", "sourceText": "the dog", "targetText": "el perro",
      "receptive":  { "familiarity": 2, "nextDueAt": null, "lastSeenAt": null, "timesSeen": 3, "timesCorrect": 2, "timesIncorrect": 1, "lastOutcome": "correct" },
      "productive": { "familiarity": 0, "nextDueAt": null, "lastSeenAt": null, "timesSeen": 0, "timesCorrect": 0, "timesIncorrect": 0, "lastOutcome": null },
      "createdAt": "2026-08-01T00:00:00.000Z", "updatedAt": "2026-08-01T00:00:00.000Z" }
    """.data(using: .utf8)!
    let item = try JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: json)
    expectNoDifference(item.receptive.familiarity, 2)
    expectNoDifference(item.receptive.lastOutcome, "correct")
    expectNoDifference(item.productive.familiarity, 0)
  }

  @Test func reviewCardIdentityCombinesItemAndDirection() {
    let card = ReviewCard(vocabItemId: "v1", sourceText: "the dog", targetText: "el perro",
      targetLanguageCode: "es", direction: .receptive, familiarity: 0, nextDueAt: nil)
    expectNoDifference(card.id, "v1#receptive")
  }
}
```

- [ ] **Step 2: Run it, verify it fails to compile** (`SRSTrack`/`ReviewCard` undefined).

Run: `make test` (or the ReviewModelsTests suite). Expected: compile failure.

- [ ] **Step 3: Rewrite `Lengua/Models/VocabItem.swift`** — add `SRSTrack`, nest tracks:

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

struct VocabItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let targetLanguageCode: String
  let sourceText: String
  let targetText: String
  let receptive: SRSTrack
  let productive: SRSTrack
  let createdAt: Date
  let updatedAt: Date
}
```

Keep `SaveVocabItemRequest` unchanged.

- [ ] **Step 4: Create `Lengua/Models/Review.swift`** with `ReviewDirection`, `ReviewOutcome`, `ReviewCard`, `DueCounts`, `ReviewQueue` exactly as in the Interfaces block above.

- [ ] **Step 5: Update `LenguaTests/VocabItem+TestSupport.swift`** so existing fixtures keep working and can set per-track familiarity:

```swift
extension SRSTrack {
  static func stub(familiarity: Int = 0) -> SRSTrack {
    SRSTrack(familiarity: familiarity, nextDueAt: nil, lastSeenAt: nil,
      timesSeen: 0, timesCorrect: 0, timesIncorrect: 0, lastOutcome: nil)
  }
}

extension VocabItem {
  init(id: String, targetLanguageCode: String, sourceText: String, targetText: String,
       receptiveFamiliarity: Int = 0, productiveFamiliarity: Int = 0,
       createdAt: Date = Date(timeIntervalSince1970: 0)) {
    self.init(
      id: id, targetLanguageCode: targetLanguageCode, sourceText: sourceText, targetText: targetText,
      receptive: .stub(familiarity: receptiveFamiliarity),
      productive: .stub(familiarity: productiveFamiliarity),
      createdAt: createdAt, updatedAt: createdAt)
  }
}
```

- [ ] **Step 6: Update memberwise fixture sites.** In `LibraryPageModelTests.swift` change the `make` helper to use the convenience init with `receptiveFamiliarity: familiarity` (drop the flat `familiarity:`/`lastSeenAt:`/… arguments). Do the same at `APIClientTests.swift:54` and `VocabItemsClientTests.swift:15` and any `TranslatePageModelTests` site passing `familiarity:`. Grep first: `git grep -n "familiarity:\|lastSeenAt:\|timesSeen:\|nextDueAt:" LenguaTests`.

- [ ] **Step 7: Update `LibraryPage.swift` familiarity sort** (`case .familiarity:` branch) to the weaker-track tuple and relabel:

```swift
case .familiarity:
  return vocabItems.items.sorted { lhs, rhs in
    let l = (min(lhs.receptive.familiarity, lhs.productive.familiarity),
             max(lhs.receptive.familiarity, lhs.productive.familiarity))
    let r = (min(rhs.receptive.familiarity, rhs.productive.familiarity),
             max(rhs.receptive.familiarity, rhs.productive.familiarity))
    if l != r { return l < r }
    return lhs.createdAt > rhs.createdAt
  }
```

And change `sortModeLabel(.familiarity)` to return `"Weakest skill"`.

- [ ] **Step 8: Run the full suite + lint.**

Run: `make test && make lint && make format-check`
Expected: all pass (new decoding tests green; existing tests green).

- [ ] **Step 9: Commit**

```bash
git add Lengua/Models/VocabItem.swift Lengua/Models/Review.swift Lengua/Views/Pages/LibraryPage.swift LenguaTests/VocabItem+TestSupport.swift LenguaTests/ReviewModelsTests.swift LenguaTests/LibraryPageModelTests.swift LenguaTests/APIClientTests.swift LenguaTests/VocabItemsClientTests.swift LenguaTests/TranslatePageModelTests.swift
git commit -m "feat(review): nest VocabItem into receptive/productive SRS tracks + review types"
```

---

### Task 2: `APIClient` — review queue + grade endpoints

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift`
- Modify: `Lengua/Core/API/APIClient+Live.swift`
- Modify: `LenguaTests/APIClientTests.swift` (or a new `ReviewAPIDecodingTests.swift`) for response-envelope decoding

**Interfaces:**
- Consumes: `ReviewQueue`, `ReviewCard`, `DueCounts`, `ReviewDirection`, `ReviewOutcome`, `VocabItem` (Task 1).
- Produces on `APIClient`:
  - `var getReviewQueue: @Sendable (_ direction: ReviewDirection?, _ limit: Int?, _ targetLanguageCode: String?) async throws -> ReviewQueue`
  - `var submitReview: @Sendable (_ vocabItemId: String, _ direction: ReviewDirection, _ outcome: ReviewOutcome) async throws -> VocabItem`
- Produces decode envelope: `struct ReviewQueueResponse: Decodable { let reviewCards: [ReviewCard]; let dueCounts: DueCounts }` (make `ReviewCard` `Decodable`; add `Codable` conformance in Task 1's `Review.swift` if not already — it is `Equatable, Sendable`; add `Codable`).

- [ ] **Step 1: Make `ReviewCard` `Codable`** — update its declaration in `Lengua/Models/Review.swift` to `Codable, Equatable, Sendable, Identifiable`. (The `id` computed var is fine; `CodingKeys` decode the stored fields only.)

- [ ] **Step 2: Write the failing decode test** in `LenguaTests/ReviewAPIDecodingTests.swift`

```swift
import Foundation
import Testing
import CustomDump
@testable import Lengua

@MainActor
@Suite struct ReviewAPIDecodingTests {
  @Test func decodesReviewQueueEnvelope() throws {
    let json = """
    { "reviewCards": [
        { "vocabItemId": "v1", "direction": "receptive", "sourceText": "the dog",
          "targetText": "el perro", "targetLanguageCode": "es", "familiarity": 0, "nextDueAt": null } ],
      "dueCounts": { "receptive": 12, "productive": 3, "total": 15 } }
    """.data(using: .utf8)!
    let decoded = try JSONDecoder.lenguaISO8601.decode(ReviewQueueResponse.self, from: json)
    expectNoDifference(decoded.reviewCards.first?.id, "v1#receptive")
    expectNoDifference(decoded.dueCounts, DueCounts(receptive: 12, productive: 3, total: 15))
  }
}
```

- [ ] **Step 3: Run it, verify failure** (`ReviewQueueResponse` undefined). Run: `make test`. Expected: compile failure.

- [ ] **Step 4: Add the client interface** to `APIClient.swift` (inside the struct, after `saveVocabItem`) and the envelope struct at file scope:

```swift
/// Fetches the caller's due review cards (auth required). `direction == nil` ⇒ "any".
var getReviewQueue:
  @Sendable (
    _ direction: ReviewDirection?, _ limit: Int?, _ targetLanguageCode: String?
  ) async throws -> ReviewQueue

/// Records the outcome of reviewing one track of one card and returns the updated item.
var submitReview:
  @Sendable (
    _ vocabItemId: String, _ direction: ReviewDirection, _ outcome: ReviewOutcome
  ) async throws -> VocabItem
```

```swift
struct ReviewQueueResponse: Decodable {
  let reviewCards: [ReviewCard]
  let dueCounts: DueCounts
}
```

- [ ] **Step 5: Run the decode test, verify it passes.** Run: `make test`. Expected: PASS.

- [ ] **Step 6: Add live implementations** to `APIClient+Live.swift` (inside the `APIClient(...)` literal, mirroring `getVocabItems`/`saveVocabItem` — bearer auth, 401 → `.unauthorized`, `JSONDecoder.lenguaISO8601`):

```swift
getReviewQueue: { direction, limit, targetLanguageCode in
  @Shared(.auth) var auth
  guard let token = auth.jwtToken, !token.isEmpty else { throw APIError.unauthorized }

  let url = baseUrl.appendingPathComponent("v1/vocab-items/review")
  var parameters: [String: Any] = ["limit": limit ?? 20]
  if let direction { parameters["direction"] = direction.rawValue }
  if let targetLanguageCode { parameters["targetLanguageCode"] = targetLanguageCode }

  let response = await session.request(
    url, parameters: parameters, encoding: URLEncoding.default,
    headers: [.authorization(bearerToken: token)]
  ).serializingData().response

  guard let http = response.response, let data = response.data else { throw APIError.dataNotValid }
  if http.statusCode == 401 { throw APIError.unauthorized }
  guard (200..<300).contains(http.statusCode) else { throw APIError.dataNotValid }
  guard let decoded = try? JSONDecoder.lenguaISO8601.decode(ReviewQueueResponse.self, from: data)
  else { throw APIError.dataNotValid }
  return ReviewQueue(cards: decoded.reviewCards, dueCounts: decoded.dueCounts)
},
submitReview: { vocabItemId, direction, outcome in
  @Shared(.auth) var auth
  guard let token = auth.jwtToken, !token.isEmpty else { throw APIError.unauthorized }

  let url = baseUrl.appendingPathComponent("v1/vocab-items/\(vocabItemId)/review")
  let response = await session.request(
    url, method: .post,
    parameters: ["direction": direction.rawValue, "outcome": outcome.rawValue],
    encoding: JSONEncoding.default,
    headers: [.authorization(bearerToken: token)]
  ).serializingData().response

  guard let http = response.response else { throw response.error ?? APIError.dataNotValid }
  if http.statusCode == 401 { throw APIError.unauthorized }
  guard (200..<300).contains(http.statusCode), let data = response.data else {
    let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
    throw APIError.validationError(body ?? "Review failed (\(http.statusCode))")
  }
  guard let item = try? JSONDecoder.lenguaISO8601.decode(VocabItem.self, from: data)
  else { throw APIError.dataNotValid }
  return item
},
```

- [ ] **Step 7: Run suite + lint.** Run: `make test && make lint && make format-check`. Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add Lengua/Core/API/APIClient.swift Lengua/Core/API/APIClient+Live.swift Lengua/Models/Review.swift LenguaTests/ReviewAPIDecodingTests.swift
git commit -m "feat(review): add getReviewQueue + submitReview API endpoints"
```

---

### Task 3: Pure forgiving typed-answer grading

**Files:**
- Create: `Lengua/Views/Pages/TypedAnswerGrading.swift`
- Create: `LenguaTests/TypedAnswerGradingTests.swift`

**Interfaces:**
- Produces: `enum TypedGrade: Equatable, Sendable { case correct, correctWithAccentNote, incorrect }` and `func gradeTypedAnswer(_ typed: String, expected: String) -> TypedGrade` (free function, `@MainActor`-free — pure).

- [ ] **Step 1: Write the failing tests** in `LenguaTests/TypedAnswerGradingTests.swift`

```swift
import Testing
import CustomDump
@testable import Lengua

@Suite struct TypedAnswerGradingTests {
  @Test func exactMatchIsCorrect() {
    expectNoDifference(gradeTypedAnswer("el perro", expected: "el perro"), .correct)
  }
  @Test func caseAndWhitespaceAndTrimNormalize() {
    expectNoDifference(gradeTypedAnswer("  EL   Perro ", expected: "el perro"), .correct)
  }
  @Test func vowelAccentDifferenceIsAccentNote() {
    expectNoDifference(gradeTypedAnswer("el pinguino", expected: "el pingüino"), .correctWithAccentNote)
    expectNoDifference(gradeTypedAnswer("cafe", expected: "café"), .correctWithAccentNote)
  }
  @Test func enyeIsADistinctLetterNotAnAccent() {
    expectNoDifference(gradeTypedAnswer("ano", expected: "año"), .incorrect)
  }
  @Test func droppedArticleIsIncorrect() {
    expectNoDifference(gradeTypedAnswer("perro", expected: "el perro"), .incorrect)
  }
  @Test func wrongWordIsIncorrect() {
    expectNoDifference(gradeTypedAnswer("gato", expected: "perro"), .incorrect)
  }
}
```

- [ ] **Step 2: Run, verify failure** (`gradeTypedAnswer` undefined). Run: `make test`. Expected: compile failure.

- [ ] **Step 3: Implement** `Lengua/Views/Pages/TypedAnswerGrading.swift`

```swift
import Foundation

enum TypedGrade: Equatable, Sendable {
  case correct
  case correctWithAccentNote
  case incorrect
}

/// Forgiving comparison of a typed productive answer to the expected target text.
/// Fixed-locale lowercasing (avoids the Turkish dotless-i trap), NFC via
/// `precomposedStringWithCanonicalMapping`, and vowel-accent-only leniency.
/// `ñ` is a distinct letter, never treated as an accent variant of `n`.
func gradeTypedAnswer(_ typed: String, expected: String) -> TypedGrade {
  let a = normalize(typed)
  let b = normalize(expected)
  if a == b { return .correct }
  if foldVowelAccents(a) == foldVowelAccents(b) { return .correctWithAccentNote }
  return .incorrect
}

private func normalize(_ s: String) -> String {
  let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
  let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  return collapsed
    .lowercased(with: Locale(identifier: "en_US_POSIX"))
    .precomposedStringWithCanonicalMapping
}

private func foldVowelAccents(_ s: String) -> String {
  let map: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u"]
  return String(s.map { map[$0] ?? $0 })
}
```

- [ ] **Step 4: Run tests, verify pass.** Run: `make test`. Expected: PASS (all 6).

- [ ] **Step 5: Lint + commit**

```bash
make lint && make format-check
git add Lengua/Views/Pages/TypedAnswerGrading.swift LenguaTests/TypedAnswerGradingTests.swift
git commit -m "feat(review): forgiving typed-answer grading (vowel-accent lenient, ñ distinct)"
```

---

### Task 4: `ReviewSessionModel` — session logic

**Files:**
- Create: `Lengua/Views/Pages/ReviewSession.swift` (model now; view added in Task 6)
- Create: `LenguaTests/ReviewSessionModelTests.swift`

**PFW:** `pfw-observable-models`, `pfw-dependencies`, `pfw-sharing`, `pfw-testing`, `pfw-custom-dump`.

**Interfaces:**
- Consumes: `ReviewCard`, `ReviewDirection`, `ReviewOutcome`, `TypedGrade`, `gradeTypedAnswer`, `APIClient.submitReview`, `@Shared(.vocabItems)`.
- Produces: `final class ReviewSessionModel: ViewModel` with:
  - `init(cards: [ReviewCard])`, `let batchCount: Int`
  - `var current: ReviewCard?`, `private(set) var isFinished: Bool`, `private(set) var resolvedCount: Int`, `private(set) var clearedCount: Int`, `var progress: Double`, `var progressText: String`
  - `var isSubmittingGrade: Bool`, `private(set) var submitFailed: Bool`
  - flip: `var isRevealed`, `func revealButtonTapped()`, `func gotItButtonTapped() async`, `func missedItButtonTapped() async`
  - type: `var typedAnswer`, `private(set) var typedGrade: TypedGrade?`, `func checkButtonTapped()`, `func markCorrectOverrideButtonTapped()`, `func continueButtonTapped() async`
  - `func retryButtonTapped() async`, `func closeButtonTapped()`

- [ ] **Step 1: Write failing tests** in `LenguaTests/ReviewSessionModelTests.swift`

```swift
import Foundation
import Dependencies
import Sharing
import Testing
import CustomDump
@testable import Lengua

@MainActor
@Suite(.serialized) struct ReviewSessionModelTests {
  private func card(_ id: String, _ dir: ReviewDirection = .receptive) -> ReviewCard {
    ReviewCard(vocabItemId: id, sourceText: "s-\(id)", targetText: "t-\(id)",
      targetLanguageCode: "es", direction: dir, familiarity: 0, nextDueAt: nil)
  }
  private func stubItem(_ id: String) -> VocabItem {
    VocabItem(id: id, targetLanguageCode: "es", sourceText: "s", targetText: "t")
  }

  @Test func correctAdvancesAndClears() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: { ReviewSessionModel(cards: [card("a"), card("b")]) }
    await model.gotItButtonTapped()
    expectNoDifference(model.current?.vocabItemId, "b")
    expectNoDifference(model.clearedCount, 1)
    expectNoDifference(model.resolvedCount, 1)
  }

  @Test func incorrectRequeuesAndStaysUntilCorrect() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: { ReviewSessionModel(cards: [card("a"), card("b")]) }
    await model.missedItButtonTapped()          // a missed -> reinserted (queue.count small -> at end)
    expectNoDifference(model.current?.vocabItemId, "b")
    expectNoDifference(model.clearedCount, 0)
    await model.gotItButtonTapped()             // b correct
    expectNoDifference(model.current?.vocabItemId, "a") // a came back
    expectNoDifference(model.isFinished, false)
  }

  @Test func cardDroppedAfterThreeMisses() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in stubItem(id) }
    } operation: { ReviewSessionModel(cards: [card("a")]) }
    await model.missedItButtonTapped()  // miss 1 -> reinsert (only card)
    await model.missedItButtonTapped()  // miss 2 -> reinsert
    await model.missedItButtonTapped()  // miss 3 -> drop
    expectNoDifference(model.isFinished, true)
    expectNoDifference(model.resolvedCount, 1)   // counts toward progress denominator
    expectNoDifference(model.clearedCount, 0)
  }

  @Test func submitFailureKeepsCardAndRetryResends() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let attempts = LockIsolated(0)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in
        attempts.withValue { $0 += 1 }
        if attempts.value == 1 { throw APIError.dataNotValid }
        return stubItem(id)
      }
    } operation: { ReviewSessionModel(cards: [card("a"), card("b")]) }
    await model.gotItButtonTapped()
    expectNoDifference(model.submitFailed, true)
    expectNoDifference(model.current?.vocabItemId, "a")   // kept
    await model.retryButtonTapped()
    expectNoDifference(model.submitFailed, false)
    expectNoDifference(model.current?.vocabItemId, "b")   // advanced
  }

  @Test func gradedResultMergedIntoSharedVocabItems() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let updated = VocabItem(id: "a", targetLanguageCode: "es", sourceText: "s", targetText: "t",
      receptiveFamiliarity: 5)
    let model = withDependencies {
      $0.api.submitReview = { _, _, _ in updated }
    } operation: { ReviewSessionModel(cards: [card("a")]) }
    await model.gotItButtonTapped()
    expectNoDifference(vocabItems.items[id: "a"]?.receptive.familiarity, 5)
  }

  @Test func typedFlowSubmitsOnlyOnContinue() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let submits = LockIsolated(0)
    let model = withDependencies {
      $0.api.submitReview = { [self] id, _, _ in submits.withValue { $0 += 1 }; return stubItem(id) }
    } operation: { ReviewSessionModel(cards: [card("a", .productive)]) }
    model.typedAnswer = "t-a"
    model.checkButtonTapped()
    expectNoDifference(model.typedGrade, .correct)
    expectNoDifference(submits.value, 0)      // nothing submitted at check time
    await model.continueButtonTapped()
    expectNoDifference(submits.value, 1)
  }
}
```

- [ ] **Step 2: Run, verify failure** (`ReviewSessionModel` undefined). Run: `make test`. Expected: compile failure.

- [ ] **Step 3: Implement the model** in `Lengua/Views/Pages/ReviewSession.swift`

```swift
import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ReviewSessionModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  init(cards: [ReviewCard]) {
    self.queue = cards
    self.batchCount = cards.count
    super.init()
  }

  // MARK: - Properties
  private var queue: [ReviewCard]
  private var missCounts: [String: Int] = [:]
  private var isClosed = false
  private var pendingOutcome: ReviewOutcome?
  private var pendingTypedOutcome: ReviewOutcome?

  let batchCount: Int
  private(set) var clearedCount = 0
  private(set) var resolvedCount = 0
  private(set) var isFinished = false
  var isSubmittingGrade = false
  private(set) var submitFailed = false

  var isRevealed = false
  var typedAnswer = ""
  private(set) var typedGrade: TypedGrade?

  // MARK: - User Actions
  func revealButtonTapped() { isRevealed = true }
  func gotItButtonTapped() async { await grade(.correct) }
  func missedItButtonTapped() async { await grade(.incorrect) }

  func checkButtonTapped() {
    guard let card = current else { return }
    let grade = gradeTypedAnswer(typedAnswer, expected: card.targetText)
    typedGrade = grade
    pendingTypedOutcome = grade == .incorrect ? .incorrect : .correct
  }
  func markCorrectOverrideButtonTapped() {
    typedGrade = .correct
    pendingTypedOutcome = .correct
  }
  func continueButtonTapped() async {
    guard let outcome = pendingTypedOutcome else { return }
    await grade(outcome)
  }
  func retryButtonTapped() async {
    guard let outcome = pendingOutcome else { return }
    await grade(outcome)
  }
  func closeButtonTapped() { isClosed = true }

  // MARK: - View Helpers
  var current: ReviewCard? { queue.first }
  var progress: Double { batchCount == 0 ? 0 : Double(resolvedCount) / Double(batchCount) }
  var progressText: String { "\(resolvedCount) of \(batchCount)" }

  // MARK: - Private Helpers
  private func grade(_ outcome: ReviewOutcome) async {
    guard let card = current, !isSubmittingGrade else { return }
    isSubmittingGrade = true
    submitFailed = false
    pendingOutcome = outcome
    do {
      let updated = try await api.submitReview(card.vocabItemId, card.direction, outcome)
      guard !isClosed else { return }
      $vocabItems.withLock { $0.items[id: updated.id] = updated }
      applyOutcome(outcome, for: card)
      resetCardState()
      isSubmittingGrade = false
    } catch {
      guard !isClosed else { return }
      submitFailed = true
      isSubmittingGrade = false
    }
  }

  private func applyOutcome(_ outcome: ReviewOutcome, for card: ReviewCard) {
    queue.removeFirst()
    switch outcome {
    case .correct:
      clearedCount += 1
      resolvedCount += 1
    case .incorrect:
      let misses = (missCounts[card.id] ?? 0) + 1
      missCounts[card.id] = misses
      if misses < 3 {
        queue.insert(card, at: min(3, queue.count))
      } else {
        resolvedCount += 1   // dropped for good
      }
    }
    if queue.isEmpty { isFinished = true }
  }

  private func resetCardState() {
    isRevealed = false
    typedAnswer = ""
    typedGrade = nil
    pendingTypedOutcome = nil
    pendingOutcome = nil
  }
}
```

- [ ] **Step 4: Run tests, verify pass.** Run: `make test`. Expected: all ReviewSessionModelTests PASS.

- [ ] **Step 5: Lint + commit**

```bash
make lint && make format-check
git add Lengua/Views/Pages/ReviewSession.swift LenguaTests/ReviewSessionModelTests.swift
git commit -m "feat(review): ReviewSessionModel — queue, grading, re-queue cap, shared merge"
```

---

### Task 5: `ReviewPageModel` — hub logic

**Files:**
- Modify: `Lengua/Views/Pages/ReviewPage.swift` (replace the placeholder model; view in Task 6)
- Create: `LenguaTests/ReviewPageModelTests.swift`

**PFW:** `pfw-observable-models`, `pfw-dependencies`, `pfw-sharing`, `pfw-testing`, `pfw-custom-dump`.

**Interfaces:**
- Consumes: `APIClient.getReviewQueue`, `@Shared(.vocabItems)`, `ReviewQueue`, `DueCounts`, `ReviewDirection`, `ReviewSessionModel`.
- Produces: `final class ReviewPageModel: ViewModel` with `enum ReviewMode: CaseIterable { case adaptive, recognition, production }`; `var mode`; `var direction: ReviewDirection?` (computed from mode); `private(set) var dueCounts: DueCounts?`; `private(set) var isLoading`, `loadFailed`; `private(set) var session: ReviewSessionModel?`; text helpers `navigationTitle`, `dueSummary`, `emptyStateText`, `startButtonTitle`, `modeLabel(_:)`; `var showsEmptyState`, `var noWordsSaved`; actions `viewAppeared() async`, `refreshDueCounts() async`, `startReviewingButtonTapped() async`, `retryButtonTapped() async`, `sessionFinished() async`.

- [ ] **Step 1: Write failing tests** in `LenguaTests/ReviewPageModelTests.swift`

```swift
import Foundation
import Dependencies
import Sharing
import Testing
import CustomDump
@testable import Lengua

@MainActor
@Suite(.serialized) struct ReviewPageModelTests {
  @Test func navigationTitleIsReview() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    expectNoDifference(ReviewPageModel().navigationTitle, "Review")
  }

  @Test func modeMapsToDirection() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewPageModel()
    model.mode = .adaptive;    expectNoDifference(model.direction, nil)
    model.mode = .recognition; expectNoDifference(model.direction, .receptive)
    model.mode = .production;  expectNoDifference(model.direction, .productive)
  }

  @Test func dueSummaryPluralizesAndReportsCaughtUp() {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let model = ReviewPageModel()
    model.setDueCountsForTesting(DueCounts(receptive: 1, productive: 3, total: 4))
    expectNoDifference(model.dueSummary, "1 to recognize · 3 to produce")
    model.setDueCountsForTesting(DueCounts(receptive: 0, productive: 0, total: 0))
    expectNoDifference(model.dueSummary, "All caught up 🎉")
  }

  @Test func emptyStateDistinguishesNoWordsFromNoneDue() {
    @Shared(.vocabItems) var vocabItems = VocabItems()   // no items
    let model = ReviewPageModel()
    model.setDueCountsForTesting(DueCounts(receptive: 0, productive: 0, total: 0))
    expectNoDifference(model.noWordsSaved, true)
    expectNoDifference(model.emptyStateText, "Save some words to review them here.")

    $vocabItems.withLock { $0.items[id: "a"] = VocabItem(id: "a", targetLanguageCode: "es", sourceText: "s", targetText: "t") }
    let model2 = ReviewPageModel()
    model2.setDueCountsForTesting(DueCounts(receptive: 0, productive: 0, total: 0))
    expectNoDifference(model2.noWordsSaved, false)
    expectNoDifference(model2.emptyStateText, "You're all caught up — check back later.")
  }

  @Test func startCreatesSessionOnlyWhenBatchNonEmpty() async {
    @Shared(.vocabItems) var vocabItems = VocabItems()
    let card = ReviewCard(vocabItemId: "a", sourceText: "s", targetText: "t",
      targetLanguageCode: "es", direction: .receptive, familiarity: 0, nextDueAt: nil)
    let model = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in ReviewQueue(cards: [card], dueCounts: DueCounts(receptive: 1, productive: 0, total: 1)) }
    } operation: { ReviewPageModel() }
    await model.startReviewingButtonTapped()
    #expect(model.session != nil)

    let empty = withDependencies {
      $0.api.getReviewQueue = { _, _, _ in ReviewQueue(cards: [], dueCounts: DueCounts(receptive: 0, productive: 0, total: 0)) }
    } operation: { ReviewPageModel() }
    await empty.startReviewingButtonTapped()
    #expect(empty.session == nil)
  }
}
```

- [ ] **Step 2: Run, verify failure.** Run: `make test`. Expected: compile failure.

- [ ] **Step 3: Implement `ReviewPageModel`** in `Lengua/Views/Pages/ReviewPage.swift` (replace the placeholder model; keep the `ReviewPage` view struct compiling — Task 6 rewrites the body, so for now make the view render `Text(model.navigationTitle)` to keep the build green):

```swift
import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ReviewPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  enum ReviewMode: CaseIterable, Sendable { case adaptive, recognition, production }
  var mode: ReviewMode = .adaptive
  private(set) var dueCounts: DueCounts?
  private(set) var isLoading = false
  private(set) var loadFailed = false
  private(set) var session: ReviewSessionModel?

  private let sessionLimit = 20

  // MARK: - User Actions
  func viewAppeared() async { await refreshDueCounts() }

  func startReviewingButtonTapped() async {
    isLoading = true
    loadFailed = false
    do {
      let queue = try await api.getReviewQueue(direction, sessionLimit, nil)
      dueCounts = queue.dueCounts
      isLoading = false
      guard !queue.cards.isEmpty else { return }
      session = ReviewSessionModel(cards: queue.cards)
    } catch {
      isLoading = false
      loadFailed = true
    }
  }

  func retryButtonTapped() async { await refreshDueCounts() }

  func sessionFinished() async {
    session = nil
    await refreshDueCounts()
  }

  // MARK: - View Helpers
  var navigationTitle: String { "Review" }
  var direction: ReviewDirection? {
    switch mode {
    case .adaptive: return nil
    case .recognition: return .receptive
    case .production: return .productive
    }
  }
  var startButtonTitle: String { "Start Reviewing" }
  var modes: [ReviewMode] { ReviewMode.allCases }
  func modeLabel(_ mode: ReviewMode) -> String {
    switch mode {
    case .adaptive: return "Adaptive"
    case .recognition: return "Recognition"
    case .production: return "Production"
    }
  }

  var totalDue: Int { dueCounts?.total ?? 0 }
  var noWordsSaved: Bool { vocabItems.items.isEmpty }
  var showsEmptyState: Bool { totalDue == 0 }

  var dueSummary: String {
    guard let counts = dueCounts, counts.total > 0 else { return "All caught up 🎉" }
    return "\(counts.receptive) to recognize · \(counts.productive) to produce"
  }
  var emptyStateText: String {
    noWordsSaved ? "Save some words to review them here."
                 : "You're all caught up — check back later."
  }
  var retryButtonTitle: String { "Try Again" }

  // MARK: - Private Helpers
  private func refreshDueCounts() async {
    isLoading = true
    loadFailed = false
    do {
      let queue = try await api.getReviewQueue(nil, 1, nil)  // any + minimal limit; read dueCounts
      dueCounts = queue.dueCounts
      isLoading = false
    } catch {
      isLoading = false
      loadFailed = true
    }
  }

  // Test seam (kept internal; not used by production code).
  func setDueCountsForTesting(_ counts: DueCounts) { dueCounts = counts }
}
```

- [ ] **Step 4: Run tests, verify pass.** Run: `make test`. Expected: ReviewPageModelTests PASS.

- [ ] **Step 5: Lint + commit**

```bash
make lint && make format-check
git add Lengua/Views/Pages/ReviewPage.swift LenguaTests/ReviewPageModelTests.swift
git commit -m "feat(review): ReviewPageModel — due counts, modes, session launch"
```

---

### Task 6: Views — hub + session UI

**Files:**
- Modify: `Lengua/Views/Pages/ReviewPage.swift` (the `ReviewPage` view body)
- Modify: `Lengua/Views/Pages/ReviewSession.swift` (add `ReviewSessionView`)

**PFW:** `pfw-modern-swiftui`.

No new unit tests (logic is covered in Tasks 3–5). Views bind to model properties/actions only — zero hardcoded strings, zero logic.

- [ ] **Step 1: Implement `ReviewPage` view** — page-blue background (reuse `LibraryPage`'s palette constants), large `navigationTitle`, a segmented `Picker` bound to `$model.mode` using `model.modes`/`model.modeLabel`, the `dueSummary`, a prominent button titled `model.startButtonTitle` calling `startReviewingButtonTapped()`, loading spinner when `isLoading`, retry (mirroring `LibraryPage`) when `loadFailed`, and the empty state (`showsEmptyState`) showing `emptyStateText`. Add `.task { await model.viewAppeared() }`. Present the session:

```swift
.fullScreenCover(isPresented: Binding(
  get: { model.session != nil },
  set: { if !$0 { Task { await model.sessionFinished() } } }
)) {
  if let session = model.session {
    ReviewSessionView(model: session, onDone: { Task { await model.sessionFinished() } })
  }
}
```

- [ ] **Step 2: Implement `ReviewSessionView`** in `ReviewSession.swift` — top row: a progress bar (`model.progress`) + `model.progressText` + a close (✕) button calling `model.closeButtonTapped()` then `onDone()`. Body switches on `model.current?.direction`:
  - `.receptive` (flip): show `current.targetText`; a reveal affordance calling `revealButtonTapped()`; once `model.isRevealed`, show `current.sourceText` and the **Missed it** / **Got it** buttons calling `missedItButtonTapped()` / `gotItButtonTapped()`.
  - `.productive` (type): show `current.sourceText`; a `TextField` bound to `$model.typedAnswer` with `.textInputAutocapitalization(.never)` and `.autocorrectionDisabled()`; a **Check** button calling `checkButtonTapped()`. When `model.typedGrade != nil`, show the result + `current.targetText` (+ accent note when `.correctWithAccentNote`), an **I was right** button (calling `markCorrectOverrideButtonTapped()`) when `.incorrect`, and a **Continue** button calling `continueButtonTapped()`.
  - When `model.submitFailed`, show a retry button calling `retryButtonTapped()`.
  - When `model.isFinished`, show the done state and a **Done** button calling `onDone()`.

  All button titles/labels come from model string properties — add any missing ones (e.g. `gotItTitle`, `missedItTitle`, `checkTitle`, `continueTitle`, `overrideTitle`, `revealHint`, `doneTitle`, `finishedText`, and `accentNote(for:)`) to `ReviewSessionModel`'s View Helpers section as literal strings.

- [ ] **Step 3: Build the app in the simulator, verify no crash and the hub renders.** Run: `make test` (compiles the app + suite). Then build/run the app target once to confirm the Review tab shows the hub. (Full flow needs the server — see Task 7.)

- [ ] **Step 4: Lint + commit**

```bash
make lint && make format-check
git add Lengua/Views/Pages/ReviewPage.swift Lengua/Views/Pages/ReviewSession.swift
git commit -m "feat(review): hub + session flashcard views"
```

---

### Task 7: Integration verification (after server lands)

**Blocked on** the server context reporting the review endpoints live and the actual serialized shapes. When that report arrives, reconcile any naming/shape differences into `VocabItem`/`Review.swift`/`APIClient+Live.swift` (and their decode tests), then verify end-to-end.

- [ ] **Step 1:** Reconcile the client models/decoders with the server's final report (field names, `dueCounts` semantics, ordering). Update decode tests to match real payloads; run `make test`.
- [ ] **Step 2:** Point the app at the running server (or a staging build), sign in, save a few vocab items, and run a full review: recognition flip cards grade + reschedule; production type cards (exact, accent-note, override); miss-then-correct re-queue; miss-3×-drop; "all caught up" state; Library "Weakest skill" sort reflects graded familiarity.
- [ ] **Step 3:** Fix any contract mismatches, commit, and run the Codex adversarial pass on the final diff per CLAUDE.md before opening the PR.

---

## Self-Review

**Spec coverage:** data model (Task 1) ✓; API methods (Task 2) ✓; forgiving typed check incl. ñ/vowel-accent/locale/NFC (Task 3) ✓; session mechanics — re-queue-until-correct, 3-miss cap, submit-then-advance, isSubmittingGrade guard, closed-session guard, retry stored outcome, merge to shared, entries-denominator (Task 4) ✓; hub — dueCounts summary, mode→direction, no-words vs none-due empty states, auth via api (Task 5) ✓; views incl. fullScreenCover(isPresented:), TextField modifiers, all-text-in-model (Task 6) ✓; LibraryPage sort + blast radius (Task 1) ✓; release coordination + integration (Task 7) ✓. Server-side dueCounts/ordering pins are tracked in the addendum, not this plan.

**Type consistency:** `ReviewSessionModel`/`ReviewPageModel` member names match between their implementations and the tests that call them; `gradeTypedAnswer`/`TypedGrade` names match across Tasks 3–4; `getReviewQueue`/`submitReview` signatures match between `APIClient` (Task 2) and their callers (Tasks 4–5).
