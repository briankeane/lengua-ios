# Lengua

Lengua's native iOS client.

## Overview

Lengua is a SwiftUI app built with an XcodeGen-generated project (no
`.xcodeproj` is committed — `project.yml` is the source of truth). It follows
an MV architecture (Model + View, no ViewModel indirection) using Point-Free's
`@Observable`-based conventions, `swift-dependencies` for dependency
injection, and `swift-sharing` for shared/persisted state.

## Prerequisites

- Xcode with the iOS 18 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), SwiftLint, and swift-format:

  ```bash
  brew install xcodegen swiftlint swift-format
  ```

- Ruby + Bundler (for fastlane, only needed for release builds):

  ```bash
  bundle install
  ```

## Quick start

```bash
make generate   # xcodegen generate -> Lengua.xcodeproj
make build      # build the app for the simulator
make test       # run the test suite
```

Other useful targets:

```bash
make lint           # swiftlint --strict
make format          # xcrun swift-format format -i (rewrites files)
make format-check    # xcrun swift-format lint --strict (no rewrites)
```

A pre-commit hook is available at `.githooks/pre-commit`; enable it with:

```bash
git config core.hooksPath .githooks
```

It formats and lints staged Swift files automatically before each commit.

## Architecture

- **Pattern**: MV with `@Observable` models — no ViewModel/Presenter layer.
  Each page is a `Model` (all text, state, and behavior) plus a `View`
  (visuals only, binds to the model).
- **Dependencies**: [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies)
  — services (API, analytics, auth) are injected via `@Dependency(\.foo)` and
  swapped for test doubles with `withDependencies`.
- **Shared state**: [`swift-sharing`](https://github.com/pointfreeco/swift-sharing)
  — persisted and in-memory app state (e.g. `@Shared(.auth)`) lives outside
  any single model and is observed reactively.
- **Networking**: `APIClient` dependency backed by a live Alamofire
  implementation (`APIClient+Live.swift`), with a controllable interface for
  tests.
- **Error reporting**: DSN-guarded Sentry integration — Sentry only
  initializes when a non-empty DSN is configured.

### Project structure

```
Lengua/
├── Config/         # Config.swift + Secrets*.xcconfig (per-environment)
├── Core/
│   ├── API/            # APIClient dependency + live implementation
│   ├── Analytics/      # AnalyticsClient dependency
│   ├── Auth/           # AuthClient dependency
│   ├── ErrorReporting/ # Sentry setup
│   └── Navigation/     # MainContainerNavigationCoordinator
├── Extensions/     # Bundle+Version, etc.
├── Models/         # Codable data models (Auth, User, AppVersionRequirements)
├── State/          # @Shared state keys
└── Views/
    ├── Pages/                  # Each page: Model + View (+ colocated Tests)
    └── Reusable Components/    # ViewModel base, LenguaAlert, etc.
LenguaTests/        # App-hosted test target
fastlane/           # Release automation (see Placeholders below)
.github/workflows/  # CI, release, release-PR
```

## Placeholders to fill in

This skeleton ships with intentional placeholders so it builds and tests
green out of the box. Before shipping to real users, fill in:

- **Sentry DSN** — `Lengua/Config/Secrets*.xcconfig` (`SENTRY_DSN`). Empty by
  default, which disables Sentry entirely.
- **Apple Developer team + App Store Connect app** — `fastlane/Appfile`
  (`apple_id`, `itc_team_id`, `team_id`).
- **`match` certificates repo** — `fastlane/Matchfile` (`git_url`).
- **GitHub Actions secrets** — `MATCH_PASSWORD` and
  `APP_STORE_CONNECT_API_KEY_ID`, referenced by `.github/workflows/release.yml`.
- **CI Xcode version** — `.github/workflows/ci.yml` and `release.yml` both
  pin `xcode-select` to `/Applications/Xcode_16.4.app`; this is illustrative
  and must be updated to match an Xcode version actually installed on the
  chosen GitHub Actions runner image (it must include the iOS 18 SDK).
- **Production `AppIcon` artwork** — `Lengua/Assets.xcassets/AppIcon.appiconset`
  currently has no images.
- **Google / Apple sign-in client IDs** — not yet wired up; add when the
  signup flow is built.

## Tests

Run `make test`, or run the `LenguaTests` scheme target from Xcode. Tests are
colocated with the code under test (e.g. `HomePage.swift` →
`HomePageTests.swift` in the same folder) and are `@MainActor`.

## Contributing

See `CLAUDE.md` for conventions AI coding agents (and humans) should follow
in this repo.
