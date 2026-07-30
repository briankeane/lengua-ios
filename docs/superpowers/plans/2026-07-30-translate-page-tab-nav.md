# Translate Page + 5-Tab Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After sign-in the user lands on a five-tab `TabView` whose first tab ("Look up") shows a Translate page matching the mockup; the other four tabs are stub screens.

**Architecture:** MV pattern — each page is an `@Observable` model (subclass of `ViewModel`) plus a colocated SwiftUI view. Models own all display text; views own visuals only. The tab shell (`MainContainer`) renders one plain `NavigationStack` per tab and binds `TabView` selection to `@Shared(.activeTab)`. Visual shell only: mic / swap / speaker / tabs are inert this pass.

**Tech Stack:** Swift 5, SwiftUI, iOS 18, XcodeGen (generated project), Point-Free `swift-sharing`, `swift-custom-dump` (tests), XCTest (app-hosted).

## Global Constraints

- **Scope:** visual shell only — no translation API, no speech-to-text, no text-to-speech, no push navigation.
- **MV split:** model owns all text; view owns visuals and text casing (`.textCase(.uppercase)`), never hardcodes strings.
- **Models:** `@MainActor @Observable final class …Model: ViewModel`, `override init() { super.init() }`.
- **Views:** `@State var model: …Model`.
- **Tests:** `@MainActor final class …: XCTestCase`, camelCase names without underscores, in `LenguaTests/`. Use `expectNoDifference` (from `CustomDump`) for value comparisons.
- **Build/test:** `make build` and `make test` run `xcodegen generate` first, so new files under `Lengua/` and `LenguaTests/` are auto-included — no `project.pbxproj` edits.
- **Do not touch:** `MainContainerNavigationCoordinator.swift` and its test, `ContentView.swift`, `SignInPage.swift`, auth.

## File Structure

- `Lengua/Views/Pages/TranslatePage.swift` — `TranslatePageModel` + `TranslatePage` view (full mockup UI).
- `Lengua/Views/Pages/DeckPage.swift`, `ReviewPage.swift`, `TalkPage.swift`, `YouPage.swift` — stub `…PageModel` + view (centered title).
- `Lengua/Views/Pages/MainContainer.swift` — rewritten `MainContainerModel` (5-tab metadata) + `MainContainer` view (5 tabs).
- `Lengua/State/SharedUserDefaults.swift` — `.activeTab` default changed to `.lookUp`.
- `LenguaTests/TranslatePageModelTests.swift`, `DeckPageModelTests.swift`, `ReviewPageModelTests.swift`, `TalkPageModelTests.swift`, `YouPageModelTests.swift`, `MainContainerModelTests.swift`.
- **Delete:** `Lengua/Views/Pages/HomePage.swift`, `LenguaTests/HomePageTests.swift`.

---

### Task 1: Stub pages (Deck, Review, Talk, You)

Four near-identical stub pages, each its own Model + View + test. Independently compilable — not yet referenced by `MainContainer`.

**Files:**
- Create: `Lengua/Views/Pages/DeckPage.swift`, `ReviewPage.swift`, `TalkPage.swift`, `YouPage.swift`
- Test: `LenguaTests/DeckPageModelTests.swift`, `ReviewPageModelTests.swift`, `TalkPageModelTests.swift`, `YouPageModelTests.swift`

**Interfaces:**
- Produces: `DeckPageModel().title == "Deck"`, `ReviewPageModel().title == "Review"`, `TalkPageModel().title == "Talk"`, `YouPageModel().title == "You"`; views `DeckPage(model:)`, `ReviewPage(model:)`, `TalkPage(model:)`, `YouPage(model:)`.

- [ ] **Step 1: Write the failing tests**

`LenguaTests/DeckPageModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class DeckPageModelTests: XCTestCase {
  func testTitleIsDeck() {
    let model = DeckPageModel()
    expectNoDifference(model.title, "Deck")
  }
}
```

`LenguaTests/ReviewPageModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class ReviewPageModelTests: XCTestCase {
  func testTitleIsReview() {
    let model = ReviewPageModel()
    expectNoDifference(model.title, "Review")
  }
}
```

`LenguaTests/TalkPageModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class TalkPageModelTests: XCTestCase {
  func testTitleIsTalk() {
    let model = TalkPageModel()
    expectNoDifference(model.title, "Talk")
  }
}
```

`LenguaTests/YouPageModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class YouPageModelTests: XCTestCase {
  func testTitleIsYou() {
    let model = YouPageModel()
    expectNoDifference(model.title, "You")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: build FAILS — `DeckPageModel` / `ReviewPageModel` / `TalkPageModel` / `YouPageModel` are undefined.

- [ ] **Step 3: Create the stub pages**

`Lengua/Views/Pages/DeckPage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class DeckPageModel: ViewModel {
  var title: String { "Deck" }

  override init() { super.init() }
}

struct DeckPage: View {
  @State var model: DeckPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
```

`Lengua/Views/Pages/ReviewPage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class ReviewPageModel: ViewModel {
  var title: String { "Review" }

  override init() { super.init() }
}

struct ReviewPage: View {
  @State var model: ReviewPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
```

`Lengua/Views/Pages/TalkPage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class TalkPageModel: ViewModel {
  var title: String { "Talk" }

  override init() { super.init() }
}

struct TalkPage: View {
  @State var model: TalkPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
```

`Lengua/Views/Pages/YouPage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class YouPageModel: ViewModel {
  var title: String { "You" }

  override init() { super.init() }
}

struct YouPage: View {
  @State var model: YouPageModel

  var body: some View {
    Text(model.title)
      .font(.largeTitle)
      .navigationTitle(model.title)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: PASS (all four new tests green; existing tests still green).

- [ ] **Step 5: Format, lint, commit**

```bash
make format
make lint
git add Lengua/Views/Pages/DeckPage.swift Lengua/Views/Pages/ReviewPage.swift Lengua/Views/Pages/TalkPage.swift Lengua/Views/Pages/YouPage.swift LenguaTests/DeckPageModelTests.swift LenguaTests/ReviewPageModelTests.swift LenguaTests/TalkPageModelTests.swift LenguaTests/YouPageModelTests.swift
git commit -m "feat: add Deck/Review/Talk/You stub pages"
```

---

### Task 2: Translate page

The "Look up" tab content, laid out to match the mockup. Model exposes all strings; view owns the blue theme, cards, and inert mic/swap/speaker buttons.

**Files:**
- Create: `Lengua/Views/Pages/TranslatePage.swift`
- Test: `LenguaTests/TranslatePageModelTests.swift`

**Interfaces:**
- Produces: `TranslatePageModel` with `englishLabel == "English"`, `englishPlaceholder == "Type or speak English"`, `speakItHint == "Speak it"`, `spanishLabel == "Spanish"`, `spanishPlaceholder == "Spanish"`; inert actions `micButtonTapped()`, `swapButtonTapped()`, `speakerButtonTapped()`; view `TranslatePage(model:)`.

- [ ] **Step 1: Write the failing test**

`LenguaTests/TranslatePageModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class TranslatePageModelTests: XCTestCase {
  func testEnglishLabel() {
    expectNoDifference(TranslatePageModel().englishLabel, "English")
  }

  func testEnglishPlaceholder() {
    expectNoDifference(TranslatePageModel().englishPlaceholder, "Type or speak English")
  }

  func testSpeakItHint() {
    expectNoDifference(TranslatePageModel().speakItHint, "Speak it")
  }

  func testSpanishLabel() {
    expectNoDifference(TranslatePageModel().spanishLabel, "Spanish")
  }

  func testSpanishPlaceholder() {
    expectNoDifference(TranslatePageModel().spanishPlaceholder, "Spanish")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: build FAILS — `TranslatePageModel` is undefined.

- [ ] **Step 3: Create the Translate page**

`Lengua/Views/Pages/TranslatePage.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class TranslatePageModel: ViewModel {
  // MARK: - Properties
  var englishLabel: String { "English" }
  var englishPlaceholder: String { "Type or speak English" }
  var speakItHint: String { "Speak it" }
  var spanishLabel: String { "Spanish" }
  var spanishPlaceholder: String { "Spanish" }

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - User Actions
  func micButtonTapped() {}
  func swapButtonTapped() {}
  func speakerButtonTapped() {}
}

struct TranslatePage: View {
  @State var model: TranslatePageModel

  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let englishCardColor = Color(red: 0.98, green: 0.98, blue: 0.96)
  private let spanishCardColor = Color(red: 0.87, green: 0.89, blue: 0.98)

  var body: some View {
    ZStack {
      pageBlue.ignoresSafeArea()

      VStack(spacing: 0) {
        englishCard
        swapButton
          .padding(.vertical, -20)
          .zIndex(1)
        spanishCard
      }
      .padding(.horizontal, 16)
    }
  }

  private var englishCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.englishLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
      Text(model.englishPlaceholder)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Text(model.speakItHint)
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: model.micButtonTapped) {
          Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(pageBlue))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20).fill(englishCardColor))
  }

  private var spanishCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.spanishLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(deepBlue)
      Text(model.spanishPlaceholder)
        .font(.largeTitle).fontWeight(.semibold)
        .foregroundStyle(deepBlue.opacity(0.45))
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Spacer()
        Button(action: model.speakerButtonTapped) {
          Image(systemName: "speaker.wave.2.fill")
            .font(.title2)
            .foregroundStyle(deepBlue)
            .frame(width: 56, height: 56)
            .background(Circle().stroke(deepBlue.opacity(0.3), lineWidth: 1))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20).fill(spanishCardColor))
  }

  private var swapButton: some View {
    Button(action: model.swapButtonTapped) {
      Image(systemName: "arrow.up.arrow.down")
        .font(.headline)
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(Circle().fill(deepBlue))
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS (five new string assertions green; existing tests still green).

- [ ] **Step 5: Format, lint, commit**

```bash
make format
make lint
git add Lengua/Views/Pages/TranslatePage.swift LenguaTests/TranslatePageModelTests.swift
git commit -m "feat: add Translate page (Look up tab) UI"
```

---

### Task 3: Five-tab shell + HomePage removal

Rewrite `MainContainerModel` to carry five-tab metadata, change the `.activeTab` default to `.lookUp`, wire `MainContainer` to the five pages, and delete the orphaned HomePage files.

**Files:**
- Modify: `Lengua/Views/Pages/MainContainer.swift`
- Modify: `Lengua/State/SharedUserDefaults.swift`
- Test: `LenguaTests/MainContainerModelTests.swift`
- Delete: `Lengua/Views/Pages/HomePage.swift`, `LenguaTests/HomePageTests.swift`

**Interfaces:**
- Consumes: `TranslatePage(model:)`, `DeckPage(model:)`, `ReviewPage(model:)`, `TalkPage(model:)`, `YouPage(model:)` from Tasks 1–2.
- Produces: `MainContainerModel.ActiveTab` cases `.lookUp, .deck, .review, .talk, .you`; per-tab title/icon accessors `lookUpTabTitle`/`lookUpTabIconName`, `deckTabTitle`/`deckTabIconName`, `reviewTabTitle`/`reviewTabIconName`, `talkTabTitle`/`talkTabIconName`, `youTabTitle`/`youTabIconName`.

- [ ] **Step 1: Write the failing test**

`LenguaTests/MainContainerModelTests.swift`:

```swift
import CustomDump
import XCTest

@testable import Lengua

@MainActor
final class MainContainerModelTests: XCTestCase {
  func testActiveTabHasFiveExpectedCases() {
    expectNoDifference(
      MainContainerModel.ActiveTab.allCases,
      [.lookUp, .deck, .review, .talk, .you]
    )
  }

  func testTabTitles() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabTitle, "Look up")
    expectNoDifference(model.deckTabTitle, "Deck")
    expectNoDifference(model.reviewTabTitle, "Review")
    expectNoDifference(model.talkTabTitle, "Talk")
    expectNoDifference(model.youTabTitle, "You")
  }

  func testTabIconNames() {
    let model = MainContainerModel()
    expectNoDifference(model.lookUpTabIconName, "magnifyingglass")
    expectNoDifference(model.deckTabIconName, "rectangle.stack")
    expectNoDifference(model.reviewTabIconName, "checkmark.square")
    expectNoDifference(model.talkTabIconName, "waveform")
    expectNoDifference(model.youTabIconName, "person")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: build FAILS — `ActiveTab.lookUp` / `lookUpTabTitle` don't exist yet (and the old `HomePageTests` still reference `HomePageModel`, deleted in Step 4).

- [ ] **Step 3: Rewrite `MainContainer.swift`**

Replace the entire contents of `Lengua/Views/Pages/MainContainer.swift` with:

```swift
import Sharing
import SwiftUI

@MainActor
@Observable
final class MainContainerModel: ViewModel {
  enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case lookUp
    case deck
    case review
    case talk
    case you
  }

  var lookUpTabTitle: String { "Look up" }
  var lookUpTabIconName: String { "magnifyingglass" }
  var deckTabTitle: String { "Deck" }
  var deckTabIconName: String { "rectangle.stack" }
  var reviewTabTitle: String { "Review" }
  var reviewTabIconName: String { "checkmark.square" }
  var talkTabTitle: String { "Talk" }
  var talkTabIconName: String { "waveform" }
  var youTabTitle: String { "You" }
  var youTabIconName: String { "person" }

  override init() { super.init() }
}

struct MainContainer: View {
  @State var model: MainContainerModel
  @Shared(.activeTab) var activeTab

  var body: some View {
    TabView(selection: Binding($activeTab)) {
      NavigationStack {
        TranslatePage(model: TranslatePageModel())
      }
      .tabItem { Label(model.lookUpTabTitle, systemImage: model.lookUpTabIconName) }
      .tag(MainContainerModel.ActiveTab.lookUp)

      NavigationStack {
        DeckPage(model: DeckPageModel())
      }
      .tabItem { Label(model.deckTabTitle, systemImage: model.deckTabIconName) }
      .tag(MainContainerModel.ActiveTab.deck)

      NavigationStack {
        ReviewPage(model: ReviewPageModel())
      }
      .tabItem { Label(model.reviewTabTitle, systemImage: model.reviewTabIconName) }
      .tag(MainContainerModel.ActiveTab.review)

      NavigationStack {
        TalkPage(model: TalkPageModel())
      }
      .tabItem { Label(model.talkTabTitle, systemImage: model.talkTabIconName) }
      .tag(MainContainerModel.ActiveTab.talk)

      NavigationStack {
        YouPage(model: YouPageModel())
      }
      .tabItem { Label(model.youTabTitle, systemImage: model.youTabIconName) }
      .tag(MainContainerModel.ActiveTab.you)
    }
  }
}
```

- [ ] **Step 4: Change the `.activeTab` default and delete HomePage files**

In `Lengua/State/SharedUserDefaults.swift`, change the `activeTab` default from `.home` to `.lookUp`:

```swift
extension SharedKey where Self == InMemoryKey<MainContainerModel.ActiveTab>.Default {
  static var activeTab: Self {
    Self[.inMemory("activeTab"), default: .lookUp]
  }
}
```

Delete the orphaned HomePage files:

```bash
git rm Lengua/Views/Pages/HomePage.swift LenguaTests/HomePageTests.swift
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: PASS (all `MainContainerModelTests` green; no remaining references to `HomePageModel`).

- [ ] **Step 6: Format, lint, commit**

```bash
make format
make lint
git add Lengua/Views/Pages/MainContainer.swift Lengua/State/SharedUserDefaults.swift LenguaTests/MainContainerModelTests.swift
git commit -m "feat: replace Home/Profile tabs with 5-tab Look up/Deck/Review/Talk/You shell"
```

---

### Task 4: App-run verification

Confirm the shell renders and behaves as intended in the running app (covers the "lands on Look up after sign-in" guarantee that is not unit-tested).

- [ ] **Step 1: Build and launch the app in the simulator**

Use the project's app-run workflow (e.g. the `run` skill, or `make build` then launch the `Lengua` scheme in an iOS 18 simulator).

- [ ] **Step 2: Sign in and verify**

Check, against `.context/attachments/hbl9Cy/image.png`:
- After sign-in the app opens on the **Look up** tab (Translate page), not another tab.
- Bottom tab bar shows five tabs in order: Look up, Deck, Review, Talk, You, with icons `magnifyingglass`, `rectangle.stack`, `checkmark.square`, `waveform`, `person`.
- Translate page shows the blue background, the "ENGLISH" card with "Type or speak English" + "Speak it" + mic button, the swap button on the seam, and the "SPANISH" card with the "Spanish" placeholder + speaker button.
- Tapping Deck / Review / Talk / You switches tabs and shows the centered stub title.

- [ ] **Step 3: Note any visual deltas**

If spacing/colors need nudging to match the mockup, adjust the view-side constants in `TranslatePage.swift` (they are purely visual), then re-run `make format && make lint` and commit with `style: match Translate page to mockup`.

---

## Self-Review

**Spec coverage:**
- 5-tab shell, default `.lookUp` → Task 3 (default) + Task 4 (verify). ✓
- Translate page mockup UI → Task 2. ✓
- Four stub pages → Task 1. ✓
- HomePage + HomePageTests deleted → Task 3 Step 4. ✓
- Coordinator/ContentView/SignIn untouched → not modified by any task. ✓
- Tests: tab cases/titles/icons, translate strings, stub titles → Tasks 1–3. ✓
- XcodeGen auto-include (no pbxproj edits) → Global Constraints. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Type consistency:** `ActiveTab` cases, `…TabTitle`/`…TabIconName` accessors, and page/model names match across Tasks 1–3 and the tests. `expectNoDifference` used consistently. ✓
