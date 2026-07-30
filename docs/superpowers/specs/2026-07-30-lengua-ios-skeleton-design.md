# Lengua iOS — Buildable Skeleton (Design)

**Date:** 2026-07-30
**Status:** Approved (pending spec review)
**Author:** Brian (with Claude)

## Goal

A buildable iOS skeleton for **Lengua** that mirrors the architecture of the
existing `playola-radio-ios` app (SwiftUI + MV/`@Observable` + Point-Free
`Dependencies`/`Sharing`). Product **features** are deferred; **infrastructure**
is built in its final form so nothing gets rebuilt later. Signup/auth flows are
**not** built yet, but the auth-gating logic is real.

Reference app: `~/playola/playola-radio-ios` (not in this repo).

## Non-goals (deferred until their feature lands)

Audio playback, CarPlay, push notifications, Mixpanel event tracking, Google/Apple
sign-in providers, and the ~25 feature pages. The skeleton demonstrates the
pattern with **one** real page (Home) end-to-end.

## Definition of done

1. `make generate` produces `Lengua.xcodeproj`.
2. `xcodebuild build` (scheme `Lengua`, an iOS 18 simulator) succeeds.
3. `xcodebuild test` runs `LenguaTests` green.
4. `make lint` and `make format-check` pass.

## Project generation — XcodeGen

- `project.yml` generates `Lengua.xcodeproj`. Regenerate with `make generate`.
- Targets:
  - `Lengua` — iOS app. Bundle IDs `com.lengua-app.lengua` (Release/Debug) and
    `com.lengua-app.lengua.staging` (Staging config). Display name **Lengua**.
  - `LenguaTests` — **logic-only** unit test bundle (NO `TEST_HOST`/`BUNDLE_LOADER`;
    the `@Shared`/`@Dependency` tests don't need app hosting). Bundle ID
    `com.lengua-app.lengua.LenguaTests`.
- Deployment target **iOS 18.0**. `SWIFT_VERSION = 5.0` (matches the proven
  reference; `@Observable` + Point-Free libs build under Swift 5 language mode).
- Build configurations: **Debug**, **Release**, **Staging**. Each maps to an
  `.xcconfig`.
- Simulator builds set `CODE_SIGNING_ALLOWED = NO`.

### SPM dependencies (exact product names — critical for XcodeGen)

| Package | URL | Products to link |
|---|---|---|
| swift-dependencies | pointfreeco/swift-dependencies | `Dependencies`, `DependenciesMacros` |
| swift-sharing | pointfreeco/swift-sharing | `Sharing` |
| swift-identified-collections | pointfreeco/swift-identified-collections | `IdentifiedCollections` |
| swift-custom-dump | pointfreeco/swift-custom-dump | `CustomDump` |
| Alamofire | Alamofire/Alamofire | `Alamofire` |
| sentry-cocoa | getsentry/sentry-cocoa | `Sentry` |

Versions pinned via `Package.resolved` (committed) after first resolve.

### Macro validation

`DependenciesMacros` triggers Xcode's macro-trust prompt on fresh machines/CI.
All `xcodebuild` invocations (Makefile + CI) pass `-skipMacroValidation`.

## Secrets / config wiring

- `.xcconfig` files drive per-config build settings and inject values into
  `Info.plist` via `$(VAR)`; read at runtime through `Bundle.main.infoDictionary`
  in `Config.swift`.
- Keys: `DEV_ENVIRONMENT`, `SENTRY_DSN` (and future tokens).
- **All `Secrets*.xcconfig` are committed with non-secret placeholder values**
  (empty `SENTRY_DSN`, `DEV_ENVIRONMENT=development`) so a fresh checkout / CI
  builds with zero setup. Files: `Secrets.xcconfig`, `Secrets-Local.xcconfig`,
  `Secrets-Staging.xcconfig`, `Secrets-Development.xcconfig`, `Secrets-Example.xcconfig`.
- When real secrets exist later, they get gitignored and `make setup-conductor`
  copies them from the origin repo (mirrors playola). Not needed until then.
- **Runtime guards:** `Config` treats an empty or unresolved (`$(`-prefixed)
  value as absent. Sentry init is skipped when `SENTRY_DSN` is absent.

## Directory layout

```
Lengua/
├── Assets.xcassets/          # AccentColor + placeholder AppIcon
├── Config/
│   ├── Config.swift
│   ├── Secrets*.xcconfig
│   └── LaunchScreen (or UILaunchScreen in Info.plist)
├── Core/
│   ├── API/                  # APIClient.swift, APIClient+Live.swift
│   ├── Analytics/            # Analytics @DependencyClient (stub)
│   ├── Auth/                 # AuthClient @DependencyClient (stub)
│   ├── ErrorReporting/       # Sentry init wrapper
│   └── Navigation/           # MainContainerNavigationCoordinator.swift
├── Extensions/               # Bundle+Version, etc.
├── Models/                   # Auth, User, AppVersionRequirements (Codable)
├── State/                    # SharedUserDefaults.swift (@Shared keys)
├── Views/
│   ├── Pages/                # ContentView, MainContainer, HomePage, SignInPage
│   └── Reusable Components/   # ViewModel.swift, LenguaAlert.swift
├── Info.plist
└── LenguaApp.swift
LenguaTests/
├── HomePageTests.swift
├── APIClientTests.swift
└── MainContainerNavigationCoordinatorTests.swift
```

## Architecture (ported in final form)

- **`LenguaApp.swift`** `@main` + `AppDelegate`: Sentry init (guarded on DSN
  presence and skipped under XCTest via `XCTestConfigurationFilePath`),
  `analytics.initialize()`. Root view is `EmptyView` under tests (mirrors
  reference), else `ContentView`.
- **`ContentView`**: `@Shared(.auth)`; renders
  `if auth.isLoggedIn { MainContainer } else { SignInPage }`.
- **`SignInPage`** (Model + View): placeholder UI; sign-in provider actions are
  no-op stubs (real providers built later). **TODO(auth):** route token storage
  through Keychain when real auth ships — do not persist real tokens in the
  file-backed `.auth` shared key.
- **`MainContainer`** (Model + View): `TabView` bound to `@Shared(.activeTab)`
  with an `ActiveTab: String, Codable, Sendable` enum (`.home`, `.profile`). Home
  tab hosts a `NavigationStack` driven by `MainContainerNavigationCoordinator`
  (holds a `Hashable` path enum). Profile tab is a placeholder.
- **`HomePage`** (Model + View + Tests): the reference pattern end-to-end.
  `@MainActor @Observable class HomePageModel: ViewModel` with
  `@ObservationIgnored @Dependency(\.api)`, `@ObservationIgnored @Shared(.auth)`,
  a `viewAppeared() async` action, and all display text as model properties.
- **`ViewModel`** base class (`@MainActor`, `Hashable` via `ObjectIdentifier`).
- **`LenguaAlert`** (`Identifiable`, `Equatable`) + `.lenguaAlert(_:)` view
  modifier (playola's `PlayolaAlert` pattern, trimmed).

### API client

- **`APIClient`** — `@DependencyClient` struct (`Dependencies` +
  `DependenciesMacros`), `Sendable`. Small real surface:
  - `getAppVersionRequirements() async throws -> AppVersionRequirements`
  - `health() async throws -> Bool` (or a `login`-shaped stub) against
    `http://localhost:10020` (server: `POST /v1/auth/{signup,login,google}` →
    `{ user, token }`).
- **`APIClient+Live`** — implemented with **Alamofire**. Base URL from `Config`.
- Registered on `DependencyValues.api`. `APIClientTests` exercise the stub
  dependency via `withDependencies`.

### State (`SharedUserDefaults.swift`)

| Key | Storage | Type |
|---|---|---|
| `.auth` | FileStorage | `Auth` (Codable, has `isLoggedIn`, default = logged-out) |
| `.activeTab` | InMemory | `ActiveTab` (default `.home`) |
| `.mainContainerNavigationCoordinator` | InMemory | `MainContainerNavigationCoordinator` |
| `.appVersionRequirements` | InMemory | `AppVersionRequirements?` (default nil) |

### Models

`Auth` (Codable; `isLoggedIn`, optional `token`/`user`), `User` (Codable),
`AppVersionRequirements` (Codable; `minimumVersion`). All explicitly
`Equatable`/`Sendable` where shared.

## Tooling

- **`.swiftlint.yml`** and **`.swiftformat`** copied from the reference. SwiftLint
  and swift-format versions pinned (SwiftLint via the SPM plugin or brew; note
  the installed version in the README) with aligned rules so both gates agree.
- **`.githooks/`** pre-commit runs `make format` + `make lint`. Build success
  never depends on hooks being installed.
- **`Makefile`** targets: `generate`, `build`, `test`, `lint`, `format`,
  `format-check`, `setup-conductor`, `release`. `build`/`test` pass
  `-skipMacroValidation` and (for simulator) `CODE_SIGNING_ALLOWED=NO`, and
  discover an available iOS 18 simulator destination.
- **fastlane**: `Fastfile`/`Appfile`/`Matchfile`/`Gemfile`/`Pluginfile` in final
  shape with clearly-marked placeholders (Apple ID, team, `match` repo, bundle
  IDs). Isolated from `make build`/`test`; release lanes fail loudly only when
  secrets are absent.
- **GitHub Actions** (no CircleCI), in `.github/workflows/`:
  - `ci.yml` — on PR: `make lint`, `make format-check`, `make generate`,
    `xcodebuild build` + `test`. Runner `macos-15`, pinned stable Xcode via
    `xcode-select` (not the local 27 beta), simulator destination discovered at
    runtime.
  - `release.yml` — manual/tag dispatch: fastlane → TestFlight on `macos-15`.
  - `release-pr.yml` — develop→main release-PR automation on `ubuntu-latest`.
- **`README.md`**, **`.gitignore`**, **`CLAUDE.md`** (points at the `pfw-*` skills
  and this architecture).

## Placeholders the user fills in later (documented in README)

Sentry DSN · Apple Developer team + App Store Connect app · `match` certs repo ·
GitHub Actions secrets · Google/Apple sign-in client IDs (when signup is built) ·
production `AppIcon` artwork (placeholder icon builds on simulator; real icon
required for TestFlight upload).

## Implementation sequencing (green-build-first)

Each stage ends compiling + committable.

1. **Skeleton project builds empty.** `project.yml` → app target + logic test
   target + Point-Free packages resolved; minimal `LenguaApp` (plain SwiftUI
   `Text`), one trivial passing test. `xcodebuild build`/`test` green.
2. **Core architecture.** `ViewModel`, `LenguaAlert`, `Config` + committed
   placeholder xcconfigs, Models, `SharedUserDefaults` `@Shared` keys,
   `ContentView` auth gate, `MainContainer` + tabs + nav coordinator, `HomePage`
   (Model/View), `SignInPage` placeholder. Tests for HomePage + nav coordinator.
3. **API layer.** `APIClient` `@DependencyClient` + `APIClient+Live` (Alamofire) +
   `APIClientTests`. Analytics/Auth `@DependencyClient` stubs.
4. **Error reporting + app delegate.** Sentry wrapper (DSN-guarded), `AppDelegate`,
   analytics `initialize()`.
5. **Tooling + CI.** swiftlint/swiftformat configs, git hooks, full Makefile,
   fastlane scaffold, GitHub Actions workflows, README/CLAUDE.md/.gitignore.

## Risks / open items

- **Xcode 27 beta local vs stable CI** — local toolchain is the 27 beta; CI pins
  a stable Xcode available on GitHub `macos-15` runners. Watch for language/SDK
  drift; deployment target 18.0 is supported on both.
- **Token storage → Keychain** when real auth ships (see SignInPage TODO).
- **Alamofire vs URLSession** — kept per "final form"; Codex would've used
  `URLSession` for a skeleton. Reversible.
