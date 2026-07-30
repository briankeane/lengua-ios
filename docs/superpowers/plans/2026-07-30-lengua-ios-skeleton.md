# Lengua iOS Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a buildable, test-green iOS skeleton for Lengua that mirrors the `playola-radio-ios` architecture (SwiftUI + MV/`@Observable` + Point-Free `Dependencies`/`Sharing`), with infrastructure in final form and product features deferred.

**Architecture:** XcodeGen generates `Lengua.xcodeproj` from `project.yml`. The app uses MV with `@Observable` models extending a `ViewModel` base, `@Dependency`-injected clients, and `@Shared` persisted/in-memory state. Tests are app-hosted XCTest bundles (`@testable import Lengua`); the app renders `EmptyView` under XCTest so hosting doesn't run the real UI.

**Tech Stack:** Swift 5, SwiftUI, iOS 18, XcodeGen, swift-dependencies, swift-sharing, swift-identified-collections, swift-custom-dump, Alamofire, sentry-cocoa, SwiftLint, swift-format, fastlane, GitHub Actions.

## Global Constraints

- Deployment target **iOS 18.0**; `SWIFT_VERSION = 5.0`.
- Bundle IDs: `com.lengua-app.lengua` (Debug/Release), `com.lengua-app.lengua.staging` (Staging), tests `com.lengua-app.lengua.LenguaTests`. Display name **Lengua**.
- Every `xcodebuild` invocation passes `-skipMacroValidation` and, for simulator, `CODE_SIGNING_ALLOWED=NO`.
- **Canonical build command:**
  `xcodebuild build -project Lengua.xcodeproj -scheme Lengua -destination "platform=iOS Simulator,name=iPhone 16" -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- **Canonical test command:**
  `xcodebuild test -project Lengua.xcodeproj -scheme Lengua -destination "platform=iOS Simulator,name=iPhone 16" -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
  (If no `iPhone 16` simulator exists, substitute any installed iOS 18 device from `xcrun simctl list devices available`.)
- **All `Secrets*.xcconfig` are committed** with non-secret placeholder values so fresh checkouts build. No real secrets in this repo yet.
- Models/state that cross `@Shared` or `@Dependency` boundaries must be explicitly `Codable`/`Equatable`/`Sendable`/`Hashable` as required.
- Regenerate the project with `make generate` after any `project.yml` change. `Lengua.xcodeproj` is gitignored; `project.yml` is the source of truth. (`Package.resolved` inside the generated project is regenerated on resolve; pin versions in `project.yml`.)
- MV pattern rules (from reference): all display text and behavior live on the model; views are visuals-only; view models are `@MainActor` and extend `ViewModel`; action methods are named for the user action (`viewAppeared`, `signInButtonTapped`).

---

## File Structure

```
project.yml                                  # XcodeGen source of truth
Makefile
.gitignore
.swiftlint.yml
.swiftformat
.githooks/pre-commit
README.md
CLAUDE.md
Gemfile
fastlane/{Appfile,Fastfile,Matchfile,Pluginfile}
.github/workflows/{ci.yml,release.yml,release-pr.yml}
Lengua/
  LenguaApp.swift                            # @main + AppDelegate
  Info.plist
  Config/
    Config.swift
    Secrets.xcconfig  Secrets-Local.xcconfig  Secrets-Staging.xcconfig
    Secrets-Development.xcconfig  Secrets-Example.xcconfig
  Assets.xcassets/{AccentColor.colorset,AppIcon.appiconset,Contents.json}
  Core/
    API/{APIClient.swift, APIClient+Live.swift}
    Analytics/AnalyticsClient.swift
    Auth/AuthClient.swift
    ErrorReporting/ErrorReporting.swift
    Navigation/MainContainerNavigationCoordinator.swift
  Extensions/Bundle+Version.swift
  Models/{Auth.swift, User.swift, AppVersionRequirements.swift}
  State/SharedUserDefaults.swift
  Views/
    Pages/{ContentView.swift, MainContainer.swift, HomePage.swift, SignInPage.swift}
    Reusable Components/{ViewModel.swift, LenguaAlert.swift}
LenguaTests/
  SmokeTests.swift
  HomePageTests.swift
  APIClientTests.swift
  MainContainerNavigationCoordinatorTests.swift
```

---

## Stage 1: Project builds and tests green (empty skeleton)

**Goal:** `make generate && make build && make test` succeed with a trivial app and one passing test. Locks in XcodeGen, package resolution, macro validation, and the app-hosted test harness before any architecture is added.

### Task 1: XcodeGen project + minimal app + smoke test

**Files:**
- Create: `project.yml`, `Makefile`, `.gitignore`
- Create: `Lengua/LenguaApp.swift`, `Lengua/Info.plist`
- Create: `Lengua/Assets.xcassets/Contents.json`, `Lengua/Assets.xcassets/AccentColor.colorset/Contents.json`, `Lengua/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Lengua/Config/Secrets.xcconfig`, `Secrets-Local.xcconfig`, `Secrets-Staging.xcconfig`, `Secrets-Development.xcconfig`, `Secrets-Example.xcconfig`
- Test: `LenguaTests/SmokeTests.swift`

**Interfaces:**
- Produces: an app target `Lengua` importing all six SPM products so later tasks can `import Dependencies`, `import Sharing`, etc.; an app-hosted test target `LenguaTests` that can `@testable import Lengua`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Xcode
*.xcodeproj
!project.yml
build/
DerivedData/
*.xcuserstate
xcuserdata/
.DS_Store

# SPM
.build/

# Secrets (only real, non-placeholder secrets go here later)
# Placeholder Secrets*.xcconfig ARE committed for now.

# Ruby / fastlane
vendor/bundle/
fastlane/report.xml
fastlane/test_output/

# Conductor scratch
.context/
```

- [ ] **Step 2: Write `project.yml`**

```yaml
name: Lengua
options:
  bundleIdPrefix: com.lengua-app
  deploymentTarget:
    iOS: "18.0"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""
    ENABLE_USER_SCRIPT_SANDBOXING: YES

configs:
  Debug: debug
  Staging: release
  Release: release

packages:
  Dependencies:
    url: https://github.com/pointfreeco/swift-dependencies
    from: "1.9.2"
  Sharing:
    url: https://github.com/pointfreeco/swift-sharing
    from: "2.5.2"
  IdentifiedCollections:
    url: https://github.com/pointfreeco/swift-identified-collections
    from: "1.1.0"
  CustomDump:
    url: https://github.com/pointfreeco/swift-custom-dump
    from: "1.3.3"
  Alamofire:
    url: https://github.com/Alamofire/Alamofire
    from: "5.10.2"
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    from: "8.44.0"

targets:
  Lengua:
    type: application
    platform: iOS
    sources:
      - path: Lengua
    configFiles:
      Debug: Lengua/Config/Secrets-Local.xcconfig
      Staging: Lengua/Config/Secrets-Staging.xcconfig
      Release: Lengua/Config/Secrets.xcconfig
    settings:
      base:
        INFOPLIST_FILE: Lengua/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        PRODUCT_BUNDLE_IDENTIFIER: com.lengua-app.lengua
        PRODUCT_NAME: Lengua
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        TARGETED_DEVICE_FAMILY: "1"
        ENABLE_TESTABILITY: YES
      configs:
        Staging:
          PRODUCT_BUNDLE_IDENTIFIER: com.lengua-app.lengua.staging
    dependencies:
      - package: Dependencies
        product: Dependencies
      - package: Dependencies
        product: DependenciesMacros
      - package: Sharing
        product: Sharing
      - package: IdentifiedCollections
        product: IdentifiedCollections
      - package: CustomDump
        product: CustomDump
      - package: Alamofire
        product: Alamofire
      - package: Sentry
        product: Sentry

  LenguaTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: LenguaTests
    dependencies:
      - target: Lengua
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lengua-app.lengua.LenguaTests
        GENERATE_INFOPLIST_FILE: YES

schemes:
  Lengua:
    build:
      targets:
        Lengua: all
        LenguaTests: [test]
    test:
      targets:
        - LenguaTests
      gatherCoverageData: false
    run:
      config: Debug
    profile:
      config: Release
    archive:
      config: Release
```

Note: the `- target: Lengua` dependency on `LenguaTests` makes XcodeGen auto-set `TEST_HOST`, `BUNDLE_LOADER`, and `TEST_TARGET_NAME` — that is what makes `@testable import Lengua` work.

- [ ] **Step 3: Write the five `Secrets*.xcconfig` files (committed placeholders)**

`Lengua/Config/Secrets-Example.xcconfig`:
```
// Copy to Secrets-Local.xcconfig and fill in real values for local dev.
DEV_ENVIRONMENT = development
SENTRY_DSN =
```

`Lengua/Config/Secrets.xcconfig` (Release):
```
DEV_ENVIRONMENT = production
SENTRY_DSN =
```

`Lengua/Config/Secrets-Local.xcconfig` (Debug):
```
DEV_ENVIRONMENT = local
SENTRY_DSN =
```

`Lengua/Config/Secrets-Staging.xcconfig` (Staging):
```
DEV_ENVIRONMENT = staging
SENTRY_DSN =
```

`Lengua/Config/Secrets-Development.xcconfig`:
```
DEV_ENVIRONMENT = development
SENTRY_DSN =
```

- [ ] **Step 4: Write `Lengua/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Lengua</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>DEV_ENVIRONMENT</key>
	<string>$(DEV_ENVIRONMENT)</string>
	<key>SENTRY_DSN</key>
	<string>$(SENTRY_DSN)</string>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 5: Write asset catalog stubs**

`Lengua/Assets.xcassets/Contents.json`:
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

`Lengua/Assets.xcassets/AccentColor.colorset/Contents.json`:
```json
{
  "colors" : [ { "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Lengua/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 6: Write minimal `Lengua/LenguaApp.swift`**

```swift
import SwiftUI

@main
struct LenguaApp: App {
  var body: some Scene {
    WindowGroup {
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        EmptyView()
      } else {
        Text("Lengua")
      }
    }
  }
}
```

- [ ] **Step 7: Write `Makefile`**

```makefile
ORIGINAL_REPO := $(HOME)/code/lengua-ios
SCHEME := Lengua
PROJECT := Lengua.xcodeproj
DESTINATION := platform=iOS Simulator,name=iPhone 16
XCFLAGS := -skipMacroValidation CODE_SIGNING_ALLOWED=NO

.PHONY: generate build test lint format format-check setup-conductor release

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" $(XCFLAGS)

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination "$(DESTINATION)" $(XCFLAGS)

lint:
	swiftlint --strict

format:
	xcrun swift-format format -i --recursive Lengua LenguaTests

format-check:
	xcrun swift-format lint --strict --recursive Lengua LenguaTests

setup-conductor:
	@test -d $(ORIGINAL_REPO) || (echo "Original repo not found at $(ORIGINAL_REPO)." && exit 1)
	@for f in Secrets Secrets-Development Secrets-Local Secrets-Staging; do \
		test -f Lengua/Config/$$f.xcconfig \
			|| cp $(ORIGINAL_REPO)/Lengua/Config/$$f.xcconfig Lengua/Config/$$f.xcconfig; \
	done

release:
	bundle exec fastlane release_production
```

- [ ] **Step 8: Write the smoke test `LenguaTests/SmokeTests.swift`**

```swift
import XCTest

@testable import Lengua

final class SmokeTests: XCTestCase {
  func testAppModuleLoads() {
    XCTAssertTrue(true)
  }
}
```

- [ ] **Step 9: Generate the project**

Run: `make generate`
Expected: `Lengua.xcodeproj` created; packages listed. If XcodeGen errors on a product name, fix `project.yml` per the exact product-name table in the spec.

- [ ] **Step 10: Run the test to verify it passes (packages resolve, host wired)**

Run: `make test`
Expected: PASS. First run resolves SPM packages (may take a minute). If it prompts about macros, confirm `-skipMacroValidation` is present.

- [ ] **Step 11: Commit**

```bash
git add project.yml Makefile .gitignore Lengua LenguaTests
git commit -m "build: XcodeGen skeleton, minimal app, green smoke test"
```

---

## Stage 2: Core architecture (state, models, pages, navigation)

**Goal:** Real MV skeleton — `ViewModel` base, `LenguaAlert`, `Config`, models, `@Shared` state, the auth-gated `ContentView`, `MainContainer` tabs, `MainContainerNavigationCoordinator`, `HomePage` (Model+View), `SignInPage` placeholder — with tests for HomePage and the nav coordinator.

### Task 2: `ViewModel` base + `Config`

**Files:**
- Create: `Lengua/Views/Reusable Components/ViewModel.swift`
- Create: `Lengua/Config/Config.swift`
- Create: `Lengua/Extensions/Bundle+Version.swift`

**Interfaces:**
- Produces: `class ViewModel` (`@MainActor`, `Hashable`); `Config.shared` with `environment: DevelopmentEnvironment` and `baseUrl: URL`; `Bundle.main.releaseVersionNumber`.

- [ ] **Step 1: Write `ViewModel.swift`**

```swift
import Foundation

@MainActor
class ViewModel: Hashable {
  init() {}

  nonisolated static func == (lhs: ViewModel, rhs: ViewModel) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}
```

- [ ] **Step 2: Write `Config.swift`**

```swift
import Foundation

enum DevelopmentEnvironment: String {
  case local, development, staging, production
}

final class Config: Sendable {
  static let shared = Config()

  let environment: DevelopmentEnvironment
  let sentryDSN: String?

  var baseUrl: URL {
    switch environment {
    case .local:
      return URL(string: "http://localhost:10020")!
    case .development, .staging, .production:
      // TODO: point staging/production at real hosts when they exist.
      return URL(string: "http://localhost:10020")!
    }
  }

  private init() {
    let rawEnv = Config.optional("DEV_ENVIRONMENT") ?? "development"
    self.environment = DevelopmentEnvironment(rawValue: rawEnv) ?? .development
    self.sentryDSN = Config.optional("SENTRY_DSN")
  }

  /// Returns nil when the Info.plist value is missing, empty, or an unresolved
  /// `$(...)` build-setting placeholder.
  static func optional(_ name: String) -> String? {
    guard let value = Bundle.main.infoDictionary?[name] as? String else { return nil }
    if value.isEmpty || value.hasPrefix("$(") { return nil }
    return value
  }
}
```

- [ ] **Step 3: Write `Bundle+Version.swift`**

```swift
import Foundation

extension Bundle {
  var releaseVersionNumber: String? {
    infoDictionary?["CFBundleShortVersionString"] as? String
  }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `make build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Lengua/Views/Reusable Components/ViewModel.swift" Lengua/Config/Config.swift Lengua/Extensions/Bundle+Version.swift
git commit -m "feat: add ViewModel base, Config, Bundle version extension"
```

### Task 3: Models

**Files:**
- Create: `Lengua/Models/User.swift`, `Lengua/Models/Auth.swift`, `Lengua/Models/AppVersionRequirements.swift`
- Test: `LenguaTests/` (covered indirectly by later tasks; no dedicated test — these are plain data types)

**Interfaces:**
- Produces: `struct User: Codable, Equatable, Sendable`; `struct Auth: Codable, Equatable, Sendable` with `var isLoggedIn: Bool` and `init()` default = logged out; `struct AppVersionRequirements: Codable, Equatable, Sendable`.

- [ ] **Step 1: Write `User.swift`**

```swift
import Foundation

struct User: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let email: String
  var firstName: String?
  var lastName: String?
  var profileImageUrl: String?
}
```

- [ ] **Step 2: Write `Auth.swift`**

```swift
import Foundation

struct Auth: Codable, Equatable, Sendable {
  var jwtToken: String?
  var currentUser: User?

  var isLoggedIn: Bool { jwtToken != nil }

  // NB: default is logged-out. This is persisted via @Shared(.auth) FileStorage.
  // TODO(auth): move token storage to Keychain before real sign-in ships;
  // do not persist real JWTs in app-container JSON.
  init(jwtToken: String? = nil, currentUser: User? = nil) {
    self.jwtToken = jwtToken
    self.currentUser = currentUser
  }
}
```

- [ ] **Step 3: Write `AppVersionRequirements.swift`**

```swift
import Foundation

struct AppVersionRequirements: Codable, Equatable, Sendable {
  let minimumVersion: String
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `make build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Lengua/Models
git commit -m "feat: add Auth, User, AppVersionRequirements models"
```

### Task 4: Navigation coordinator (+ test)

**Files:**
- Create: `Lengua/Core/Navigation/MainContainerNavigationCoordinator.swift`
- Test: `LenguaTests/MainContainerNavigationCoordinatorTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class MainContainerNavigationCoordinator` with `var path: [Path]`, `enum Path: Hashable`, `func push(_:)`, `func pop()`, `func popToRoot()`. `Path` cases: `.profile` (placeholder for future detail pages).

- [ ] **Step 1: Write the failing test `MainContainerNavigationCoordinatorTests.swift`**

```swift
import XCTest

@testable import Lengua

@MainActor
final class MainContainerNavigationCoordinatorTests: XCTestCase {
  func testPushAppendsToPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    XCTAssertEqual(coordinator.path, [.profile])
  }

  func testPopRemovesLast() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.pop()
    XCTAssertEqual(coordinator.path, [])
  }

  func testPopToRootClearsPath() {
    let coordinator = MainContainerNavigationCoordinator()
    coordinator.push(.profile)
    coordinator.push(.profile)
    coordinator.popToRoot()
    XCTAssertEqual(coordinator.path, [])
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `MainContainerNavigationCoordinator` not found.

- [ ] **Step 3: Write `MainContainerNavigationCoordinator.swift`**

```swift
import Foundation

@MainActor
@Observable
final class MainContainerNavigationCoordinator {
  enum Path: Hashable {
    case profile
  }

  var path: [Path] = []

  init(path: [Path] = []) {
    self.path = path
  }

  func push(_ item: Path) { path.append(item) }
  func pop() { _ = path.popLast() }
  func popToRoot() { path.removeAll() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Lengua/Core/Navigation LenguaTests/MainContainerNavigationCoordinatorTests.swift
git commit -m "feat: add MainContainerNavigationCoordinator with tests"
```

### Task 5: `@Shared` state keys

**Files:**
- Create: `Lengua/State/SharedUserDefaults.swift`

**Interfaces:**
- Produces `SharedKey` extensions: `.auth` (FileStorage<Auth>, default `Auth()`), `.activeTab` (InMemory<MainContainerModel.ActiveTab>, default `.home`), `.mainContainerNavigationCoordinator` (InMemory, default new instance), `.appVersionRequirements` (InMemory<AppVersionRequirements?>, default nil).
- Consumes: `MainContainerModel.ActiveTab` — **defined in Task 6**; this file will not compile until Task 6 lands. Implement Task 5 and Task 6 together before running `make build`.

- [ ] **Step 1: Write `SharedUserDefaults.swift`**

```swift
import Foundation
import Sharing

extension SharedKey where Self == FileStorageKey<Auth>.Default {
  static var auth: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "auth.json")), default: Auth()]
  }
}

extension SharedKey where Self == InMemoryKey<MainContainerModel.ActiveTab>.Default {
  static var activeTab: Self {
    Self[.inMemory("activeTab"), default: .home]
  }
}

extension SharedKey where Self == InMemoryKey<MainContainerNavigationCoordinator>.Default {
  static var mainContainerNavigationCoordinator: Self {
    Self[.inMemory("mainContainerNavigationCoordinator"), default: MainContainerNavigationCoordinator()]
  }
}

extension SharedKey where Self == InMemoryKey<AppVersionRequirements?>.Default {
  static var appVersionRequirements: Self {
    Self[.inMemory("appVersionRequirements"), default: nil]
  }
}
```

- [ ] **Step 2: (No build yet — depends on Task 6.)** Proceed to Task 6, then build.

- [ ] **Step 3: Commit (after Task 6 builds green)**

```bash
git add Lengua/State/SharedUserDefaults.swift
git commit -m "feat: add @Shared state keys"
```

### Task 6: `LenguaAlert`, `MainContainer` (Model+View), `HomePage` placeholder-free, `SignInPage`, `ContentView`

**Files:**
- Create: `Lengua/Views/Reusable Components/LenguaAlert.swift`
- Create: `Lengua/Views/Pages/MainContainer.swift`
- Create: `Lengua/Views/Pages/HomePage.swift`
- Create: `Lengua/Views/Pages/SignInPage.swift`
- Create: `Lengua/Views/Pages/ContentView.swift`
- Test: `LenguaTests/HomePageTests.swift`

**Interfaces:**
- Produces: `struct LenguaAlert` + `.lenguaAlert(_:)`; `MainContainerModel` with `enum ActiveTab: String, Codable, Sendable, CaseIterable { case home, profile }`; `HomePageModel` with `navigationTitle`, `greeting`, `viewAppeared() async`; `SignInPageModel` with `signInButtonTapped()`; `ContentView`.
- Consumes: `@Shared(.auth)`, `@Shared(.activeTab)`, `@Shared(.mainContainerNavigationCoordinator)` from Task 5; `@Dependency(\.api)` from Stage 3 (until then, HomePageModel uses no api; add api in Stage 3).

- [ ] **Step 1: Write `LenguaAlert.swift`**

```swift
import SwiftUI

@MainActor
struct LenguaAlert: Identifiable, Equatable, Hashable {
  nonisolated let id = UUID()
  nonisolated let title: String
  nonisolated let message: String?

  init(title: String, message: String? = nil) {
    self.title = title
    self.message = message
  }

  nonisolated static func == (lhs: LenguaAlert, rhs: LenguaAlert) -> Bool {
    lhs.title == rhs.title && lhs.message == rhs.message
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(title)
    hasher.combine(message)
  }
}

extension View {
  func lenguaAlert(_ alert: Binding<LenguaAlert?>) -> some View {
    self.alert(
      alert.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { alert.wrappedValue != nil },
        set: { if !$0 { alert.wrappedValue = nil } }
      ),
      presenting: alert.wrappedValue,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { presented in if let msg = presented.message { Text(msg) } }
    )
  }
}
```

- [ ] **Step 2: Write the failing test `HomePageTests.swift`**

```swift
import Sharing
import XCTest

@testable import Lengua

@MainActor
final class HomePageTests: XCTestCase {
  func testNavigationTitleIsHome() {
    let model = HomePageModel()
    XCTAssertEqual(model.navigationTitle, "Home")
  }

  func testGreetingUsesFirstNameWhenLoggedIn() {
    @Shared(.auth) var auth = Auth(
      jwtToken: "token",
      currentUser: User(id: "1", email: "a@b.com", firstName: "Sam", lastName: nil, profileImageUrl: nil)
    )
    let model = HomePageModel()
    XCTAssertEqual(model.greeting, "Hola, Sam!")
  }

  func testGreetingFallsBackWhenNoName() {
    @Shared(.auth) var auth = Auth()
    let model = HomePageModel()
    XCTAssertEqual(model.greeting, "Hola!")
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `HomePageModel` not found.

- [ ] **Step 4: Write `HomePage.swift`**

```swift
import Sharing
import SwiftUI

@MainActor
@Observable
final class HomePageModel: ViewModel {
  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Properties
  var presentedAlert: LenguaAlert?

  // MARK: - View Helpers
  var navigationTitle: String { "Home" }

  var greeting: String {
    if let firstName = auth.currentUser?.firstName, !firstName.isEmpty {
      return "Hola, \(firstName)!"
    }
    return "Hola!"
  }

  var bodyText: String { "Welcome to Lengua. This is the skeleton home page." }

  // MARK: - User Actions
  override init() { super.init() }

  func viewAppeared() async {
    // Placeholder for future data loading (Stage 3 wires @Dependency(\.api)).
  }
}

struct HomePage: View {
  @State var model: HomePageModel

  var body: some View {
    VStack(spacing: 16) {
      Text(model.greeting).font(.largeTitle).bold()
      Text(model.bodyText).foregroundStyle(.secondary)
    }
    .padding()
    .navigationTitle(model.navigationTitle)
    .lenguaAlert($model.presentedAlert)
    .task { await model.viewAppeared() }
  }
}
```

- [ ] **Step 5: Write `SignInPage.swift`**

```swift
import Sharing
import SwiftUI

@MainActor
@Observable
final class SignInPageModel: ViewModel {
  @ObservationIgnored @Shared(.auth) var auth

  var titleText: String { "Lengua" }
  var subtitleText: String { "Sign in to get started." }
  var signInButtonTitle: String { "Sign In" }

  override init() { super.init() }

  // Placeholder: real Apple/Google sign-in providers are built later.
  // For skeleton bring-up this is a no-op stub.
  func signInButtonTapped() {
    // TODO(auth): implement real sign-in and set $auth.
  }
}

struct SignInPage: View {
  @State var model: SignInPageModel

  var body: some View {
    VStack(spacing: 24) {
      Text(model.titleText).font(.largeTitle).bold()
      Text(model.subtitleText).foregroundStyle(.secondary)
      Button(model.signInButtonTitle) { model.signInButtonTapped() }
        .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
```

- [ ] **Step 6: Write `MainContainer.swift`**

```swift
import Sharing
import SwiftUI

@MainActor
@Observable
final class MainContainerModel: ViewModel {
  enum ActiveTab: String, Codable, Sendable, CaseIterable {
    case home
    case profile
  }

  override init() { super.init() }
}

struct MainContainer: View {
  @State var model: MainContainerModel
  @Shared(.activeTab) var activeTab
  @Shared(.mainContainerNavigationCoordinator) var coordinator

  var body: some View {
    TabView(selection: Binding($activeTab)) {
      NavigationStack(path: Binding(get: { coordinator.path }, set: { coordinator.path = $0 })) {
        HomePage(model: HomePageModel())
      }
      .tabItem { Label("Home", systemImage: "house") }
      .tag(MainContainerModel.ActiveTab.home)

      NavigationStack {
        Text("Profile").navigationTitle("Profile")
      }
      .tabItem { Label("Profile", systemImage: "person") }
      .tag(MainContainerModel.ActiveTab.profile)
    }
  }
}
```

- [ ] **Step 7: Write `ContentView.swift`**

```swift
import Sharing
import SwiftUI

@MainActor
struct ContentView: View {
  @Shared(.auth) var auth

  var mainContainerModel = MainContainerModel()

  var body: some View {
    Group {
      if auth.isLoggedIn {
        MainContainer(model: mainContainerModel)
      } else {
        SignInPage(model: SignInPageModel())
      }
    }
  }
}
```

- [ ] **Step 8: Point `LenguaApp` at `ContentView`**

Replace the body of `Lengua/LenguaApp.swift`'s non-test branch:

```swift
import SwiftUI

@main
struct LenguaApp: App {
  var body: some Scene {
    WindowGroup {
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        EmptyView()
      } else {
        ContentView()
      }
    }
  }
}
```

- [ ] **Step 9: Run tests to verify pass (this also compiles Task 5's state file)**

Run: `make test`
Expected: PASS (SmokeTests, HomePageTests, MainContainerNavigationCoordinatorTests).
If `Binding($activeTab)` / `Binding(get:set:)` type errors appear, adjust the TabView selection and NavigationStack path bindings to match your Sharing version's binding API (both `@Shared` values expose `$`-projected bindings).

- [ ] **Step 10: Commit**

```bash
git add "Lengua/Views" Lengua/State/SharedUserDefaults.swift Lengua/LenguaApp.swift LenguaTests/HomePageTests.swift
git commit -m "feat: add LenguaAlert, MainContainer, HomePage, SignInPage, ContentView, shared state"
```

---

## Stage 3: API layer (Alamofire) + client stubs

**Goal:** `APIClient` `@DependencyClient` with a live Alamofire implementation and a small real surface; `Analytics` and `Auth` client stubs; `APIClientTests` using the test dependency. Wire `@Dependency(\.api)` into `HomePageModel`.

### Task 7: `APIClient` dependency + live implementation + tests

**Files:**
- Create: `Lengua/Core/API/APIClient.swift`, `Lengua/Core/API/APIClient+Live.swift`
- Modify: `Lengua/Views/Pages/HomePage.swift` (inject `@Dependency(\.api)`)
- Test: `LenguaTests/APIClientTests.swift`

**Interfaces:**
- Produces: `struct APIClient: Sendable` (`@DependencyClient`) with `var getAppVersionRequirements: @Sendable () async throws -> AppVersionRequirements` and `var health: @Sendable () async throws -> Bool`; `DependencyValues.api`; `enum APIError: Error`.
- Consumes: `Config.shared.baseUrl`, `AppVersionRequirements` (Task 3).

- [ ] **Step 1: Write the failing test `APIClientTests.swift`**

```swift
import Dependencies
import XCTest

@testable import Lengua

@MainActor
final class APIClientTests: XCTestCase {
  func testGetAppVersionRequirementsUsesInjectedDependency() async throws {
    let result = try await withDependencies {
      $0.api.getAppVersionRequirements = { AppVersionRequirements(minimumVersion: "1.2.3") }
    } operation: {
      @Dependency(\.api) var api
      return try await api.getAppVersionRequirements()
    }
    XCTAssertEqual(result.minimumVersion, "1.2.3")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `api` dependency not found.

- [ ] **Step 3: Write `APIClient.swift`**

```swift
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct APIClient: Sendable {
  /// Fetches minimum app version requirements (no auth required).
  var getAppVersionRequirements: @Sendable () async throws -> AppVersionRequirements = {
    AppVersionRequirements(minimumVersion: "0.0.0")
  }

  /// Simple server reachability check against the configured base URL.
  var health: @Sendable () async throws -> Bool = { true }
}

enum APIError: Error, LocalizedError {
  case dataNotValid
  case validationError(String)

  var errorDescription: String? {
    switch self {
    case .dataNotValid: return "Invalid data received from server"
    case .validationError(let message): return message
    }
  }
}

extension DependencyValues {
  var api: APIClient {
    get { self[APIClient.self] }
    set { self[APIClient.self] = newValue }
  }
}

extension APIClient: TestDependencyKey {
  static let testValue = APIClient()
}
```

- [ ] **Step 4: Write `APIClient+Live.swift`**

```swift
import Alamofire
import Dependencies
import Foundation

extension APIClient: DependencyKey {
  static let liveValue: APIClient = {
    let session = Session()
    let baseUrl = Config.shared.baseUrl

    return APIClient(
      getAppVersionRequirements: {
        let url = baseUrl.appendingPathComponent("v1/app-version-requirements")
        let data = try await session.request(url).serializingData().value
        guard let requirements = try? JSONDecoder().decode(AppVersionRequirements.self, from: data)
        else { throw APIError.dataNotValid }
        return requirements
      },
      health: {
        let url = baseUrl.appendingPathComponent("health")
        let response = await session.request(url).serializingData().response
        return response.response?.statusCode == 200
      }
    )
  }()
}
```

- [ ] **Step 5: Inject `@Dependency(\.api)` into `HomePageModel`**

In `Lengua/Views/Pages/HomePage.swift`, add to `HomePageModel` after the shared-state MARK:

```swift
  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api
```

and add `import Dependencies` at the top. Leave `viewAppeared()` as a no-op for now (or optionally call `try? await api.health()` — keep it side-effect-free for tests).

- [ ] **Step 6: Run tests to verify pass**

Run: `make test`
Expected: PASS. `APIClientTests` proves the dependency is injectable; `@DependencyClient` synthesizes the test client so unset endpoints report unimplemented.

- [ ] **Step 7: Commit**

```bash
git add Lengua/Core/API LenguaTests/APIClientTests.swift Lengua/Views/Pages/HomePage.swift
git commit -m "feat: add APIClient dependency, Alamofire live client, tests"
```

### Task 8: Analytics + Auth client stubs

**Files:**
- Create: `Lengua/Core/Analytics/AnalyticsClient.swift`, `Lengua/Core/Auth/AuthClient.swift`

**Interfaces:**
- Produces: `DependencyValues.analytics` with `var initialize: @Sendable () async -> Void`; `DependencyValues.authClient` with `var signOut: @Sendable () async -> Void`. Both live values are no-ops (real implementations land with their features).

- [ ] **Step 1: Write `AnalyticsClient.swift`**

```swift
import Dependencies
import DependenciesMacros

@DependencyClient
struct AnalyticsClient: Sendable {
  var initialize: @Sendable () async -> Void
}

extension AnalyticsClient: DependencyKey {
  // No-op until a real analytics provider (e.g. Mixpanel) is added.
  static let liveValue = AnalyticsClient(initialize: {})
  static let testValue = AnalyticsClient(initialize: {})
}

extension DependencyValues {
  var analytics: AnalyticsClient {
    get { self[AnalyticsClient.self] }
    set { self[AnalyticsClient.self] = newValue }
  }
}
```

- [ ] **Step 2: Write `AuthClient.swift`**

```swift
import Dependencies
import DependenciesMacros
import Sharing

@DependencyClient
struct AuthClient: Sendable {
  var signOut: @Sendable () async -> Void
}

extension AuthClient: DependencyKey {
  static let liveValue = AuthClient(
    signOut: {
      @Shared(.auth) var auth
      $auth.withLock { $0 = Auth() }
    }
  )
  static let testValue = AuthClient(signOut: {})
}

extension DependencyValues {
  var authClient: AuthClient {
    get { self[AuthClient.self] }
    set { self[AuthClient.self] = newValue }
  }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `make build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Lengua/Core/Analytics Lengua/Core/Auth
git commit -m "feat: add Analytics and Auth dependency-client stubs"
```

---

## Stage 4: Error reporting + AppDelegate

**Goal:** DSN-guarded Sentry init behind a small wrapper; `AppDelegate` wiring Sentry + analytics init; app skips side effects under XCTest.

### Task 9: Error reporting wrapper + AppDelegate

**Files:**
- Create: `Lengua/Core/ErrorReporting/ErrorReporting.swift`
- Modify: `Lengua/LenguaApp.swift`

**Interfaces:**
- Produces: `enum ErrorReporting { static func start() }` — starts Sentry only when `Config.shared.sentryDSN` is non-nil and not running under XCTest.

- [ ] **Step 1: Write `ErrorReporting.swift`**

```swift
import Foundation
import Sentry

enum ErrorReporting {
  static func start() {
    let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    guard !isRunningTests, let dsn = Config.shared.sentryDSN else { return }

    SentrySDK.start { options in
      options.dsn = dsn
      options.sendDefaultPii = false
      options.tracesSampleRate = 0.1
    }
  }
}
```

- [ ] **Step 2: Update `LenguaApp.swift` with an AppDelegate**

```swift
import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    ErrorReporting.start()
    return true
  }
}

@main
struct LenguaApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    Task {
      @Dependency(\.analytics) var analytics
      await analytics.initialize()
    }
  }

  var body: some Scene {
    WindowGroup {
      if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        EmptyView()
      } else {
        ContentView()
      }
    }
  }
}
```

Add `import Dependencies` at the top of the file.

- [ ] **Step 3: Run tests to verify still green**

Run: `make test`
Expected: PASS. Sentry does not start under tests (guarded), and DSN is empty anyway.

- [ ] **Step 4: Commit**

```bash
git add Lengua/Core/ErrorReporting Lengua/LenguaApp.swift
git commit -m "feat: add DSN-guarded Sentry init and AppDelegate"
```

---

## Stage 5: Tooling, CI, docs

**Goal:** Lint/format configs, git hooks, fastlane scaffold, GitHub Actions, and docs. Build/test remain green; `make lint` and `make format-check` pass.

### Task 10: SwiftLint + swift-format + git hooks

**Files:**
- Create: `.swiftlint.yml`, `.swiftformat`, `.githooks/pre-commit`

**Interfaces:**
- Produces: passing `make lint` and `make format-check` on the current tree.

- [ ] **Step 1: Write `.swiftlint.yml`**

```yaml
disabled_rules:
  - trailing_whitespace
  - trailing_comma
  - todo

line_length:
  warning: 120
  error: 200

identifier_name:
  min_length:
    warning: 2
    error: 1
  allowed_symbols:
    - "_"

file_length:
  warning: 1000
  error: 1000

excluded:
  - .build
  - Lengua.xcodeproj
```

- [ ] **Step 2: Write `.swiftformat`**

```
--swiftversion 5.0
```

- [ ] **Step 3: Write `.githooks/pre-commit`**

```bash
#!/bin/sh
set -e
xcrun swift-format format -i --recursive Lengua LenguaTests
swiftlint --strict --quiet
git add -u
```

Make it executable and register the hooks path:

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

- [ ] **Step 4: Run format then lint**

Run: `make format && make format-check && make lint`
Expected: format rewrites nothing new; format-check and lint PASS. Fix any violations reported (e.g. import ordering) and re-run.

- [ ] **Step 5: Commit**

```bash
git add .swiftlint.yml .swiftformat .githooks
git commit -m "chore: add swiftlint, swift-format, pre-commit hook"
```

### Task 11: fastlane scaffold

**Files:**
- Create: `Gemfile`, `fastlane/Appfile`, `fastlane/Matchfile`, `fastlane/Pluginfile`, `fastlane/Fastfile`

**Interfaces:**
- Produces: `fastlane release_production` / `release_staging` lanes that fail loudly with a clear message when required secrets/placeholders are absent (so they never run accidentally in `make build`/`test`).

- [ ] **Step 1: Write `Gemfile`**

```ruby
source "https://rubygems.org"

gem "fastlane", ">= 2.229.0"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
```

- [ ] **Step 2: Write `fastlane/Pluginfile`**

```ruby
# gem "fastlane-plugin-..." # add plugins here as needed
```

- [ ] **Step 3: Write `fastlane/Appfile`**

```ruby
# PLACEHOLDER — fill in when the App Store Connect app exists.
app_identifier "com.lengua-app.lengua"
apple_id "PLACEHOLDER_APPLE_ID"      # e.g. "you@example.com"
itc_team_id "PLACEHOLDER_ITC_TEAM"   # App Store Connect team id
team_id "PLACEHOLDER_TEAM_ID"        # Developer Portal team id
```

- [ ] **Step 4: Write `fastlane/Matchfile`**

```ruby
# PLACEHOLDER — fill in when the match certs repo exists.
git_url("PLACEHOLDER_MATCH_GIT_URL")
storage_mode("git")
type("appstore")
app_identifier(["com.lengua-app.lengua", "com.lengua-app.lengua.staging"])
```

- [ ] **Step 5: Write `fastlane/Fastfile`**

```ruby
default_platform(:ios)

REQUIRED_ENV = %w[MATCH_PASSWORD APP_STORE_CONNECT_API_KEY_ID].freeze

def ensure_release_secrets!
  missing = REQUIRED_ENV.reject { |k| ENV[k] && !ENV[k].empty? }
  unless missing.empty?
    UI.user_error!("Release secrets not configured: #{missing.join(', ')}. " \
                   "This is a scaffold — fill in Appfile/Matchfile and CI secrets first.")
  end
end

platform :ios do
  desc "Build and upload production to TestFlight"
  lane :release_production do
    ensure_release_secrets!
    setup_ci if ENV["CI"]
    match(type: "appstore", readonly: true)
    build_app(scheme: "Lengua", xcargs: "-skipMacroValidation")
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end

  desc "Build and upload staging to TestFlight"
  lane :release_staging do
    ensure_release_secrets!
    setup_ci if ENV["CI"]
    match(type: "appstore", readonly: true)
    build_app(scheme: "Lengua", configuration: "Staging", xcargs: "-skipMacroValidation")
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```

- [ ] **Step 6: Verify the Fastfile parses**

Run: `bundle install && bundle exec fastlane lanes`
Expected: lists `release_production` and `release_staging`. (If Ruby/bundler is not set up, skip execution — the scaffold is still committed. Note this in the commit.)

- [ ] **Step 7: Commit**

```bash
git add Gemfile fastlane
git commit -m "chore: add fastlane scaffold with placeholder credentials"
```

### Task 12: GitHub Actions workflows

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/release-pr.yml`

**Interfaces:**
- Produces: CI that lints, format-checks, generates, builds, and tests on macOS; a manual release workflow; a develop→main release-PR workflow.

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]

jobs:
  build-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select stable Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app

      - name: Install tools
        run: brew install xcodegen swiftlint swift-format

      - name: Generate project
        run: xcodegen generate

      - name: Lint
        run: swiftlint --strict

      - name: Format check
        run: swift-format lint --strict --recursive Lengua LenguaTests

      - name: Pick a simulator
        id: sim
        run: |
          DEVICE=$(xcrun simctl list devices available | grep -m1 "iPhone" | sed -E 's/^[[:space:]]*([^(]+) \(.*/\1/' | xargs)
          echo "device=$DEVICE" >> "$GITHUB_OUTPUT"

      - name: Build & test
        run: |
          xcodebuild test \
            -project Lengua.xcodeproj -scheme Lengua \
            -destination "platform=iOS Simulator,name=${{ steps.sim.outputs.device }}" \
            -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Note: `Xcode_16.4.app` is an example. Adjust to a version actually present on the runner image (check the runner's `xcodes installed` or the runner-images release notes) — deployment target 18.0 needs an Xcode that ships the iOS 18 SDK.

- [ ] **Step 2: Write `.github/workflows/release.yml`**

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      lane:
        description: "fastlane lane"
        required: true
        default: release_production
        type: choice
        options: [release_production, release_staging]

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select stable Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
      - name: Install tools
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Run lane
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
        run: bundle exec fastlane ${{ inputs.lane }}
```

- [ ] **Step 3: Write `.github/workflows/release-pr.yml`**

```yaml
name: Release PR

on:
  workflow_dispatch:

jobs:
  release-pr:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Open develop -> main release PR
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh pr create --base main --head develop \
            --title "Release" \
            --body "Automated release PR from develop to main." \
            || echo "PR may already exist."
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows
git commit -m "ci: add GitHub Actions CI, release, and release-PR workflows"
```

### Task 13: README + CLAUDE.md

**Files:**
- Create: `README.md`, `CLAUDE.md`

**Interfaces:**
- Produces: setup docs listing every placeholder the user must fill in.

- [ ] **Step 1: Write `README.md`**

Include: overview; prerequisites (Xcode with iOS 18 SDK, `brew install xcodegen swiftlint swift-format`, Ruby/bundler for fastlane); quick start (`make generate`, `make build`, `make test`); architecture summary (MV + `@Observable` + Dependencies + Sharing); and a **"Placeholders to fill in"** section listing: Sentry DSN (`Secrets*.xcconfig`), Apple Developer team + App Store Connect app (`fastlane/Appfile`), `match` repo (`fastlane/Matchfile`), GitHub Actions secrets (`MATCH_PASSWORD`, `APP_STORE_CONNECT_API_KEY_ID`), CI Xcode version in `ci.yml`/`release.yml`, production `AppIcon` artwork, and Google/Apple sign-in client IDs (when signup is built).

- [ ] **Step 2: Write `CLAUDE.md`**

Mirror the reference's guidance, adapted to Lengua: point at the `pfw-*` skills (mandatory before writing Swift), the MV/`@Observable` pattern, tests colocated and `@MainActor`, `@Shared` state usage, `make format`/`make lint`, and the server docs location (`~/code/lengua/server`).

- [ ] **Step 3: Final full verification**

Run: `make generate && make build && make test && make lint && make format-check`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add README and CLAUDE.md"
```

---

## Self-Review (completed)

**Spec coverage:** XcodeGen (T1) ✓; bundle IDs/config (T1) ✓; committed placeholder xcconfigs (T1) ✓; Info.plist keys + AppIcon (T1) ✓; macro validation + signing flags (Global Constraints, T1) ✓; ViewModel/Config (T2) ✓; models (T3) ✓; nav coordinator (T4) ✓; `@Shared` state (T5) ✓; LenguaAlert/MainContainer/HomePage/SignInPage/ContentView (T6) ✓; APIClient + Alamofire live + tests (T7) ✓; Analytics/Auth stubs (T8) ✓; Sentry DSN-guarded + AppDelegate (T9) ✓; swiftlint/swiftformat/hooks (T10) ✓; fastlane (T11) ✓; GitHub Actions, no CircleCI (T12) ✓; README/CLAUDE.md (T13) ✓; app-hosted tests + EmptyView-under-test (T1/T6/global) ✓; Keychain TODO surfaced (T3/T6) ✓.

**Placeholder scan:** The only intentional placeholders are credential values in `fastlane/*` and `Secrets*.xcconfig`, each explicitly marked and documented in the README — these are user-supplied secrets, not plan gaps. No `TODO`-without-code steps.

**Type consistency:** `Auth.isLoggedIn`/`jwtToken`/`currentUser`, `User` fields, `AppVersionRequirements.minimumVersion`, `MainContainerModel.ActiveTab.{home,profile}`, `MainContainerNavigationCoordinator.{path,push,pop,popToRoot,Path.profile}`, `APIClient.{getAppVersionRequirements,health}`, `DependencyValues.{api,analytics,authClient}` are referenced consistently across tasks.

**Known integration risk to watch during execution:** the exact `@Shared` → SwiftUI `Binding` bridging in `MainContainer` (TabView selection + NavigationStack path) can vary by `swift-sharing` version; Task 6 Step 9 calls this out. If the version's API differs, adapt the binding construction — the model/state contract does not change.
