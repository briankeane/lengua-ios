# Translate Page + 5-Tab Navigation — Design

**Date:** 2026-07-30
**Scope:** Visual shell only. No working translation, speech-to-text, or
text-to-speech in this pass.

## Goal

After sign-in the user lands on a five-tab `TabView`. The first tab, **Look up**,
shows the **Translate** page laid out to match the provided mockup. The other four
tabs (**Deck, Review, Talk, You**) are minimal stub screens. Tab bar, mic, swap,
and speaker controls are inert placeholders this pass; real behavior lands in
follow-up PRs.

## Non-Goals

- Translation API calls, microphone / speech-to-text, text-to-speech.
- Push navigation inside any tab (no destinations yet).
- Real content for Deck / Review / Talk / You.
- Any change to auth, `SignInPage`, or `ContentView` routing.

## Current State

- `MainContainer` is a two-tab `TabView` (Home, Profile) driven by
  `@Shared(.activeTab)` over `MainContainerModel.ActiveTab { .home, .profile }`.
- `@Shared(.activeTab)` is an `InMemoryKey`, default `.home` (no persistence, so
  changing the enum has no migration risk).
- `MainContainerNavigationCoordinator` has a single `path: [Path]` with
  `Path { .profile }`, plus `push/pop/popToRoot`, covered by
  `MainContainerNavigationCoordinatorTests`.
- `ContentView` routes `auth.isLoggedIn ? MainContainer : SignInPage`.
- Project is generated with **XcodeGen** (`project.yml`, folder-based sources,
  `createIntermediateGroups: true`). `make build` / `make test` run
  `xcodegen generate` first, so new `.swift` files under `Lengua/` and
  `LenguaTests/` are auto-included. No `project.pbxproj` editing.

## Architecture

MV pattern throughout: each page is an `@Observable` model (subclass of
`ViewModel`) plus a colocated SwiftUI view. The **model owns all display text and
behavior**; the **view owns visuals only** and never hardcodes strings. Text
casing (e.g. uppercase language labels) is a view-side presentation concern via
`.textCase(.uppercase)`, so model strings stay `"English"` / `"Spanish"`.

### Tab shell — `MainContainer` / `MainContainerModel`

- Replace `ActiveTab` cases with `.lookUp, .deck, .review, .talk, .you`.
- Change the `.activeTab` shared default from `.home` to `.lookUp`.
- `MainContainerModel` exposes, per tab, a title and an SF Symbol name:
  - Look up — `"Look up"` / `magnifyingglass`
  - Deck — `"Deck"` / `rectangle.stack`
  - Review — `"Review"` / `checkmark.square`
  - Talk — `"Talk"` / `waveform`
  - You — `"You"` / `person`
- `MainContainer` renders one plain `NavigationStack { …Page(model:) }` per tab,
  each with `.tabItem { Label(title, systemImage:) }` and `.tag(...)`, selection
  bound to `@Shared(.activeTab)`.
- **Drop** the `coordinator.path` binding from `MainContainer` (no push
  destinations yet). **Leave `MainContainerNavigationCoordinator` and its test
  untouched** — trimming `Path.profile` would be unrelated churn.

### Translate page — `TranslatePage` / `TranslatePageModel`

Matches the mockup:

- Blue background.
- **English input card** (top): uppercase language label, large placeholder
  "Type or speak English", a "Speak it" hint at the bottom-left and a circular
  microphone button at the bottom-right.
- **Swap button**: a circular up/down-arrows button centered between the cards.
- **Spanish output card** (bottom): uppercase language label, "Spanish"
  placeholder, a circular speaker button at the bottom-right.

`TranslatePageModel` exposes every string, e.g.:
`englishLabel = "English"`, `englishPlaceholder = "Type or speak English"`,
`speakItHint = "Speak it"`, `spanishLabel = "Spanish"`,
`spanishPlaceholder = "Spanish"` (plus a nav title if needed). The view supplies
colors, card shapes, fonts, spacing, icon sizes, and applies uppercase casing.
Mic / swap / speaker are rendered buttons with empty / no-op actions this pass.

### Stub pages — `DeckPage`, `ReviewPage`, `TalkPage`, `YouPage`

Each is a `…PageModel` exposing a `title: String` and a view rendering a centered
`Text(model.title)`. No shared abstraction beyond the `ViewModel` base. They exist
as real files so future PRs fill them in without restructuring the tab shell.

### HomePage removal

`HomePage.swift` and `HomePageTests.swift` become orphaned once Home leaves the
tab set. Both are **deleted**. Because the project is XcodeGen-generated, deletion
just drops them from the target on the next `generate`; no `project.pbxproj`
churn.

## Data Flow

`@Shared(.activeTab)` (in-memory) holds the selected tab; `MainContainer` binds
`TabView` selection to it and defaults to `.lookUp`. No other shared state
changes. No network, no persistence.

## Error Handling

None required — this is inert UI. No API, no failable operations, no alerts.

## Testing

App-hosted `XCTest`, `@MainActor`, colocated in `LenguaTests/`, camelCase names.
Use `pfw-custom-dump` (`expectNoDifference`) for value comparisons where it fits.

- `MainContainerModelTests`: `ActiveTab` has exactly the five expected cases; each
  of the five tab titles and icon names is correct. (The "lands on Look up after
  sign-in" default is process-global in-memory state — asserting it in a unit test
  is order-dependent/flaky, so it is verified by running the app rather than a unit
  test.)
- `TranslatePageModelTests`: asserts the display strings (labels, placeholders,
  hint).
- `DeckPageModelTests`, `ReviewPageModelTests`, `TalkPageModelTests`,
  `YouPageModelTests`: each asserts its `title`.
- Delete `HomePageTests.swift`.
- Leave `MainContainerNavigationCoordinatorTests` and other tests unchanged.

## Files

**Add** (under `Lengua/Views/Pages/`): `TranslatePage.swift`, `DeckPage.swift`,
`ReviewPage.swift`, `TalkPage.swift`, `YouPage.swift`.
**Add** (under `LenguaTests/`): `TranslatePageModelTests.swift`,
`MainContainerModelTests.swift`, and one small test file per stub page.
**Edit:** `MainContainer.swift`, `SharedUserDefaults.swift` (activeTab default).
**Delete:** `HomePage.swift`, `HomePageTests.swift`.
**Untouched:** `MainContainerNavigationCoordinator.swift` + its test,
`ContentView.swift`, `SignInPage.swift`, auth.
