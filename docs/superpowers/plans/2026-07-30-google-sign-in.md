# Google Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Point-Free skills are mandatory in this repo.** Before writing code in a task, invoke the relevant `pfw-*` skills: `pfw-dependencies` (any `@DependencyClient`/`@Dependency`), `pfw-observable-models` (the `SignInPageModel`), `pfw-testing` + `pfw-custom-dump` (all tests — use `expectNoDifference`, not raw `==`), `pfw-sharing` (`@Shared(.auth)`), `pfw-modern-swiftui` (the view).

**Goal:** Replace the placeholder `SignInPage` with a working Sign-in-with-Google flow that matches the approved mockup; the Apple button is present but disabled.

**Architecture:** MV with an `@Observable` `SignInPageModel`. The model runs the GoogleSignIn SDK, sends the resulting **idToken** to `POST /v1/auth/google`, and on success writes `@Shared(.auth)` so `ContentView` flips to `MainContainer`. Supporting dependency clients (analytics, error reporting) and error classification are ported from `~/playola/playola-radio-ios` and adapted to Lengua.

**Tech Stack:** Swift, SwiftUI, `@Observable`, Point-Free `swift-dependencies` / `swift-sharing` / `swift-custom-dump`, Alamofire, GoogleSignIn-iOS SDK, XcodeGen, XCTest.

## Global Constraints

- Deployment target iOS 18.0; Swift 5.0 (from `project.yml`).
- Xcode project is **generated** by XcodeGen from `project.yml`. After editing `project.yml`, run `make generate`. Never hand-edit a `.xcodeproj` (none is committed).
- Tests are app-hosted XCTest, `@MainActor`, run via `make test`. Test naming: camelCase, no underscores. Colocate model tests under `LenguaTests/`.
- Models own all display text/behavior; views bind to model properties and hold zero logic (MV pattern per `CLAUDE.md`).
- All view models inherit the `ViewModel` base class and are `@MainActor @Observable final`.
- Alerts use `LenguaAlert`; navigation/auth state via `@Shared`.
- iOS OAuth client ID (not a secret): `458159274501-45e0d61m9v4710girp004e1io6bdatdv.apps.googleusercontent.com`. Reversed-client-ID URL scheme: `com.googleusercontent.apps.458159274501-45e0d61m9v4710girp004e1io6bdatdv`. Server `GOOGLE_CLIENT_ID` matches this (confirmed by user).
- Support email in alert copy: `lonesomewhistle@gmail.com`.
- Run `make format` then `make lint` before each commit; commits must build. Do NOT use `--no-verify`. Do NOT add `Co-Authored-By` trailers.

---

### Task 1: Wire GoogleSignIn SDK, Info.plist, assets, and test-target deps

**Files:**
- Modify: `project.yml` (add package + target deps)
- Modify: `Lengua/Info.plist` (GIDClientID + URL scheme)
- Create: `Lengua/Assets.xcassets/google-icon.imageset/` (copied from Playola)
- Create: `Lengua/Assets.xcassets/LogoMark.imageset/` (Lengua logo mark)

**Interfaces:**
- Produces: linkable `import GoogleSignIn` / `import GoogleSignInSwift`; asset names `"google-icon"` and `"LogoMark"`; test-target access to `ConcurrencyExtras` (`LockIsolated`) and `CustomDump` (`expectNoDifference`).

- [ ] **Step 1: Add the GoogleSignIn package to `project.yml`**

Under `packages:` add:

```yaml
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
    from: "8.0.0"
  ConcurrencyExtras:
    url: https://github.com/pointfreeco/swift-concurrency-extras
    from: "1.1.0"
```

- [ ] **Step 2: Add product deps to the `Lengua` target in `project.yml`**

Under `targets: Lengua: dependencies:` append:

```yaml
      - package: GoogleSignIn
        product: GoogleSignIn
      - package: GoogleSignIn
        product: GoogleSignInSwift
```

- [ ] **Step 3: Add test-target deps to `LenguaTests` in `project.yml`**

Under `targets: LenguaTests: dependencies:` append:

```yaml
      - package: CustomDump
        product: CustomDump
        link: false
      - package: ConcurrencyExtras
        product: ConcurrencyExtras
        link: false
```

- [ ] **Step 4: Add Google keys to `Lengua/Info.plist`**

Insert these keys inside the root `<dict>` (e.g. after the `CFBundleVersion` entry). Keep alphabetical-ish grouping; exact position does not matter:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string></string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>com.googleusercontent.apps.458159274501-45e0d61m9v4710girp004e1io6bdatdv</string>
			</array>
		</dict>
	</array>
	<key>GIDClientID</key>
	<string>458159274501-45e0d61m9v4710girp004e1io6bdatdv.apps.googleusercontent.com</string>
```

- [ ] **Step 5: Copy the `google-icon` asset from Playola**

Run:

```bash
cp -R ~/playola/playola-radio-ios/PlayolaRadio/Assets.xcassets/google-icon.imageset \
  Lengua/Assets.xcassets/google-icon.imageset
```

- [ ] **Step 6: Create the `LogoMark` imageset**

The repo has no logo artwork (`AppIcon.appiconset` is an empty 1024 placeholder) and Playola's `LogoMark` is Playola's logo. Create a placeholder imageset from the approved mockup so the view compiles and renders the correct mark:

```bash
mkdir -p Lengua/Assets.xcassets/LogoMark.imageset
# Crop the logo mark region out of the approved mockup as a placeholder PNG.
sips -c 340 340 --cropOffset 300 250 \
  .context/attachments/uRr3WY/image.png \
  --out Lengua/Assets.xcassets/LogoMark.imageset/LogoMark.png
```

Then write `Lengua/Assets.xcassets/LogoMark.imageset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "LogoMark.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

If the crop offsets look off after the first build, adjust `--cropOffset`. Flag to the user that this is a placeholder pending real artwork.

- [ ] **Step 7: Regenerate and build**

Run: `make build`
Expected: XcodeGen resolves the new packages and the app compiles (the stub `SignInPage` is untouched). If SwiftPM needs to resolve GoogleSignIn for the first time, the build may take longer.

- [ ] **Step 8: Commit**

```bash
git add project.yml Lengua/Info.plist Lengua/Assets.xcassets/google-icon.imageset Lengua/Assets.xcassets/LogoMark.imageset
git commit -m "chore: add GoogleSignIn SDK, Info.plist config, and sign-in assets"
```

---

### Task 2: Port support types (analytics event, error-reporting client, key-window, alerts)

**Files:**
- Create: `Lengua/Core/Analytics/AnalyticsEvent.swift`
- Modify: `Lengua/Core/Analytics/AnalyticsClient.swift`
- Create: `Lengua/Core/ErrorReporting/ErrorReportingClient.swift`
- Create: `Lengua/Extensions/UIApplication+keyWindow.swift`
- Modify: `Lengua/Views/Reusable Components/LenguaAlert.swift`

**Interfaces:**
- Produces:
  - `enum AnalyticsEvent: Equatable { signInStarted(method:), signInCompleted(method:userId:), signInFailed(method:error:) }`, `enum AuthMethod: String { apple, google }`
  - `AnalyticsClient.track: @Sendable (AnalyticsEvent) async -> Void`
  - `@Dependency(\.errorReporting) ErrorReportingClient` with `reportError`, `reportErrorWithContext`, `reportMessage`; plus `.noop`
  - `SignInAPIError`, `NetworkErrorClassifier`, `SignInErrorReport`
  - `UIApplication.keyWindowPresentedController: UIViewController?`
  - `LenguaAlert.signInError`, `LenguaAlert.signInNetworkError`

- [ ] **Step 1: Create `Lengua/Core/Analytics/AnalyticsEvent.swift`**

```swift
enum AnalyticsEvent: Equatable {
  case signInStarted(method: AuthMethod)
  case signInCompleted(method: AuthMethod, userId: String)
  case signInFailed(method: AuthMethod, error: String)
}

enum AuthMethod: String {
  case apple
  case google
}
```

- [ ] **Step 2: Add `track` to `Lengua/Core/Analytics/AnalyticsClient.swift`**

Replace the struct + registrations so `track` is added while keeping `initialize`:

```swift
import Dependencies
import DependenciesMacros

@DependencyClient
struct AnalyticsClient: Sendable {
  var initialize: @Sendable () async -> Void
  var track: @Sendable (_ event: AnalyticsEvent) async -> Void
}

extension AnalyticsClient: DependencyKey {
  // No-op until a real analytics provider (e.g. Mixpanel) is added.
  static let liveValue = AnalyticsClient(initialize: {}, track: { _ in })
  static let testValue = AnalyticsClient(initialize: {}, track: { _ in })
}

extension DependencyValues {
  var analytics: AnalyticsClient {
    get { self[AnalyticsClient.self] }
    set { self[AnalyticsClient.self] = newValue }
  }
}
```

- [ ] **Step 3: Create `Lengua/Core/ErrorReporting/ErrorReportingClient.swift`**

Port from Playola verbatim (no Playola-specific strings live in this file). Full content:

```swift
import Alamofire
import Dependencies
import DependenciesMacros
import Foundation

#if canImport(Sentry)
  import Sentry
#endif

// MARK: - Error Reporting Client Dependency

@DependencyClient
struct ErrorReportingClient: Sendable {
  var reportError: @Sendable (_ error: Error, _ tags: [String: String]) async -> Void
  var reportErrorWithContext:
    @Sendable (
      _ error: Error, _ tags: [String: String], _ contextKey: String, _ context: [String: String]
    ) async -> Void
  var reportMessage: @Sendable (_ message: String, _ tags: [String: String]) async -> Void
}

extension ErrorReportingClient: TestDependencyKey {
  static let testValue = ErrorReportingClient.noop
}

extension DependencyValues {
  var errorReporting: ErrorReportingClient {
    get { self[ErrorReportingClient.self] }
    set { self[ErrorReportingClient.self] = newValue }
  }
}

extension ErrorReportingClient: DependencyKey {
  static let liveValue = Self(
    reportError: { error, tags in
      #if canImport(Sentry)
        SentrySDK.capture(error: error) { scope in
          for (key, value) in tags { scope.setTag(value: value, key: key) }
        }
      #endif
    },
    reportErrorWithContext: { error, tags, contextKey, context in
      #if canImport(Sentry)
        SentrySDK.capture(error: error) { scope in
          for (key, value) in tags { scope.setTag(value: value, key: key) }
          if !context.isEmpty { scope.setContext(value: context, key: contextKey) }
        }
      #endif
    },
    reportMessage: { message, tags in
      #if canImport(Sentry)
        SentrySDK.capture(message: message) { scope in
          for (key, value) in tags { scope.setTag(value: value, key: key) }
        }
      #endif
    }
  )
}

extension ErrorReportingClient {
  static let noop = Self(
    reportError: { _, _ in },
    reportErrorWithContext: { _, _, _, _ in },
    reportMessage: { _, _ in }
  )
}

struct SignInAPIError: Error, LocalizedError {
  let authMethod: AuthMethod
  let endpointPath: String
  let statusCode: Int?
  let responseBody: String?
  let underlyingError: Error

  var errorDescription: String? {
    var description = "Sign-in API exchange failed for \(authMethod.rawValue)"
    if let statusCode { description += " with HTTP \(statusCode)" }
    description += ": \(underlyingError.localizedDescription)"
    return description
  }
}

enum NetworkErrorClassifier {
  static let networkErrorCodes: Set<Int> = [
    NSURLErrorSecureConnectionFailed,
    NSURLErrorNotConnectedToInternet,
    NSURLErrorTimedOut,
    NSURLErrorCannotConnectToHost,
    NSURLErrorNetworkConnectionLost,
  ]

  static func isNetworkError(_ error: Error) -> Bool {
    nsURLErrorCodes(in: error).contains { networkErrorCodes.contains($0) }
  }

  static func isSecureConnectionFailed(_ error: Error) -> Bool {
    nsURLErrorCodes(in: error).contains(NSURLErrorSecureConnectionFailed)
  }

  static func errorTags(for error: Error) -> [String: String] {
    let nsError = walkErrors(error).first { $0.domain == NSURLErrorDomain } ?? error as NSError
    return ["error_domain": nsError.domain, "error_code": "\(nsError.code)"]
  }

  private static func nsURLErrorCodes(in error: Error) -> [Int] {
    walkErrors(error).compactMap { $0.domain == NSURLErrorDomain ? $0.code : nil }
  }

  private static func walkErrors(_ error: Error) -> [NSError] {
    var collected: [NSError] = []
    var queue: [Error] = [error]
    var iterations = 0
    while !queue.isEmpty, iterations < 16 {
      let next = queue.removeFirst()
      iterations += 1
      let ns = next as NSError
      collected.append(ns)
      if let afError = next as? AFError {
        if let underlying = afError.underlyingError { queue.append(underlying) }
      } else if let signInError = next as? SignInAPIError {
        queue.append(signInError.underlyingError)
      } else if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
        queue.append(underlying)
      }
      queue.append(contentsOf: ns.underlyingErrors)
    }
    return collected
  }
}

struct SignInErrorReport {
  let contextKey = "sign_in"
  let tags: [String: String]
  let context: [String: String]

  init(error: Error, authMethod: AuthMethod, step: String) {
    var tags = ["auth_method": authMethod.rawValue, "sign_in_step": step]
    var context: [String: String] = [:]

    let errorForDomain = (error as? SignInAPIError)?.underlyingError ?? error
    let nsError = errorForDomain as NSError
    tags["error_domain"] = nsError.domain
    tags["error_code"] = "\(nsError.code)"

    if let apiError = error as? SignInAPIError {
      tags["endpoint_path"] = apiError.endpointPath
      if let statusCode = apiError.statusCode { tags["http_status_code"] = "\(statusCode)" }
      context["endpoint_path"] = apiError.endpointPath
      if let responseBody = apiError.responseBody {
        context["response_body"] = Self.redactedResponseBody(responseBody)
        context["response_body_bytes"] = "\(responseBody.lengthOfBytes(using: .utf8))"
        if let keys = Self.topLevelJSONKeys(responseBody), !keys.isEmpty {
          context["response_body_top_level_keys"] = keys.joined(separator: ",")
        }
      }
    }

    self.tags = tags
    self.context = context
  }

  private static func redactedResponseBody(_ responseBody: String) -> String {
    guard let data = responseBody.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data)
    else { return responseBody }

    let redacted = redactSensitiveValues(in: json)
    guard JSONSerialization.isValidJSONObject(redacted),
      let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
      let redactedString = String(data: redactedData, encoding: .utf8)
    else { return responseBody }
    return redactedString
  }

  private static func redactSensitiveValues(in value: Any) -> Any {
    if let dictionary = value as? [String: Any] {
      return dictionary.reduce(into: [String: Any]()) { result, item in
        if shouldRedact(key: item.key) {
          result[item.key] = "[REDACTED]"
        } else {
          result[item.key] = redactSensitiveValues(in: item.value)
        }
      }
    }
    if let array = value as? [Any] { return array.map { redactSensitiveValues(in: $0) } }
    return value
  }

  private static func shouldRedact(key: String) -> Bool {
    let normalizedKey = key.lowercased()
    return normalizedKey.contains("token")
      || normalizedKey == "authcode"
      || normalizedKey == "authorizationcode"
  }

  private static func topLevelJSONKeys(_ responseBody: String) -> [String]? {
    guard let data = responseBody.data(using: .utf8),
      let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return dictionary.keys.sorted()
  }
}
```

- [ ] **Step 4: Create `Lengua/Extensions/UIApplication+keyWindow.swift`**

Verbatim port:

```swift
import Foundation
import SwiftUI

extension UIApplication {
  public var keyWindow: UIWindow? {
    Self
      .shared
      .connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .last { $0.isKeyWindow }
  }

  public var keyWindowPresentedController: UIViewController? {
    var viewController = keyWindow?.rootViewController

    if let presentedController = viewController as? UITabBarController {
      viewController = presentedController.selectedViewController
    }

    while let presentedController = viewController?.presentedViewController {
      if let presentedController = presentedController as? UITabBarController {
        viewController = presentedController.selectedViewController
      } else {
        viewController = presentedController
      }
    }
    return viewController
  }
}
```

- [ ] **Step 5: Add alert factories to `Lengua/Views/Reusable Components/LenguaAlert.swift`**

Append this extension (below the existing `extension View`):

```swift
extension LenguaAlert {
  static var signInError: LenguaAlert {
    LenguaAlert(
      title: "Sign-In Failed",
      message:
        "Something went wrong on our end while signing you in. Please try again. "
        + "If it keeps happening, contact us at lonesomewhistle@gmail.com and we'll "
        + "help get you sorted.")
  }

  static var signInNetworkError: LenguaAlert {
    LenguaAlert(
      title: "Connection Issue",
      message:
        "Your network is blocking the secure connection to Lengua. Try turning "
        + "off wifi and using cellular data, or switch to a different wifi "
        + "network. (More info: https://support.apple.com/en-us/122756)")
  }
}
```

- [ ] **Step 6: Build**

Run: `make build`
Expected: compiles. (`AnalyticsEvent`, `ErrorReportingClient`, key-window, alerts all resolve; no consumer yet.)

- [ ] **Step 7: Commit**

```bash
git add Lengua/Core/Analytics Lengua/Core/ErrorReporting "Lengua/Views/Reusable Components/LenguaAlert.swift" Lengua/Extensions/UIApplication+keyWindow.swift
git commit -m "feat: add analytics track, error-reporting client, key-window helper, sign-in alerts"
```

---

### Task 3: Add the Google sign-in API method

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift`
- Modify: `Lengua/Core/API/APIClient+Live.swift`
- Test: `LenguaTests/APIClientTests.swift` (add a decoding test)

**Interfaces:**
- Consumes: `User` (`id, email, firstName?, lastName?, profileImageUrl?`), `SignInAPIError`, `APIError`.
- Produces: `struct GoogleSignInResult: Equatable, Sendable { let user: User; let token: String }` and `APIClient.signInViaGoogle: @Sendable (_ idToken: String) async throws -> GoogleSignInResult`.

- [ ] **Step 1: Write the failing decoding test in `LenguaTests/APIClientTests.swift`**

Add (inside the existing test class, keeping its imports; add `@testable import Lengua` if missing):

```swift
func testGoogleSignInResponseDecodesUserAndToken() throws {
  let json = Data(
    """
    {
      "user": {
        "id": "u1",
        "firstName": "Sam",
        "lastName": "Lee",
        "displayName": "Sam Lee",
        "email": "sam@example.com",
        "profileImageUrl": "https://img/1.png",
        "role": "user"
      },
      "token": "jwt-123"
    }
    """.utf8)

  let decoded = try JSONDecoder().decode(GoogleSignInResponse.self, from: json)

  XCTAssertEqual(decoded.token, "jwt-123")
  XCTAssertEqual(decoded.user.id, "u1")
  XCTAssertEqual(decoded.user.email, "sam@example.com")
  XCTAssertEqual(decoded.user.firstName, "Sam")
  XCTAssertEqual(decoded.user.profileImageUrl, "https://img/1.png")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test`
Expected: FAIL — `GoogleSignInResponse` is undefined.

- [ ] **Step 3: Add the types and client method to `Lengua/Core/API/APIClient.swift`**

Add above `enum APIError`:

```swift
struct GoogleSignInResult: Equatable, Sendable {
  let user: User
  let token: String
}

/// Decodes the `POST /v1/auth/google` response `{ user, token }`.
/// Extra server fields (`displayName`, `role`) are intentionally ignored.
struct GoogleSignInResponse: Decodable {
  struct APIUser: Decodable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
  }
  let user: APIUser
  let token: String

  var result: GoogleSignInResult {
    GoogleSignInResult(
      user: User(
        id: user.id, email: user.email, firstName: user.firstName,
        lastName: user.lastName, profileImageUrl: user.profileImageUrl),
      token: token)
  }
}
```

Then add this property to the `APIClient` struct (after `health`):

```swift
  /// Exchanges a Google ID token for a Lengua session (JWT + user).
  var signInViaGoogle: @Sendable (_ idToken: String) async throws -> GoogleSignInResult
```

- [ ] **Step 4: Run the decoding test to verify it passes**

Run: `make test`
Expected: PASS for `testGoogleSignInResponseDecodesUserAndToken`.

- [ ] **Step 5: Implement `signInViaGoogle` in `Lengua/Core/API/APIClient+Live.swift`**

Add `import Foundation` is already present. Add the closure to the `APIClient(...)` initializer (after `health`):

```swift
      signInViaGoogle: { idToken in
        let path = "v1/auth/google"
        let url = baseUrl.appendingPathComponent(path)
        let response = await session.request(
          url,
          method: .post,
          parameters: ["idToken": idToken],
          encoding: JSONEncoding.default
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)", statusCode: nil,
            responseBody: nil, underlyingError: response.error ?? APIError.dataNotValid)
        }

        let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
        guard (200..<300).contains(httpResponse.statusCode) else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: response.error ?? APIError.dataNotValid)
        }

        guard let data = response.data,
          let decoded = try? JSONDecoder().decode(GoogleSignInResponse.self, from: data)
        else {
          throw SignInAPIError(
            authMethod: .google, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: APIError.dataNotValid)
        }

        return decoded.result
      }
```

Add `import Alamofire` is already present in `+Live.swift`; `JSONEncoding` comes from Alamofire.

- [ ] **Step 6: Build**

Run: `make build`
Expected: compiles.

- [ ] **Step 7: Commit**

```bash
git add Lengua/Core/API LenguaTests/APIClientTests.swift
git commit -m "feat: add signInViaGoogle API client method and response decoding"
```

---

### Task 4: Build `SignInPageModel` (TDD)

**Files:**
- Modify: `Lengua/Views/Pages/SignInPage.swift` (model only in this task; view in Task 5)
- Test: `LenguaTests/SignInPageTests.swift`

**Interfaces:**
- Consumes: `\.api` (`signInViaGoogle`), `\.analytics` (`track`), `\.errorReporting`, `@Shared(.auth)`, `AnalyticsEvent`/`AuthMethod`, `LenguaAlert`, `NetworkErrorClassifier`, `SignInErrorReport`, `UIApplication.keyWindowPresentedController`, GoogleSignIn SDK.
- Produces: `SignInPageModel` with `titleText`, `subtitleText`, `googleSignInButtonTitle`, `appleSignInButtonTitle`, `isAppleSignInEnabled`, `presentedAlert`, injectable `keyWindowProvider`, `signInWithGoogleButtonTapped() async`, `appleSignInButtonTapped()`, and internal `handleSignInAPIFailure(_:authMethod:step:) async`.

- [ ] **Step 1: Write the failing tests in `LenguaTests/SignInPageTests.swift`**

```swift
import Alamofire
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import Sharing
import XCTest

@testable import Lengua

@MainActor
final class SignInPageTests: XCTestCase {
  func testDisplayTextMatchesMockup() {
    @Shared(.auth) var auth = Auth()
    let model = SignInPageModel()
    XCTAssertEqual(model.titleText, "Lengua")
    XCTAssertEqual(model.subtitleText, "Look it up. Keep it. Say it back.")
    XCTAssertEqual(model.googleSignInButtonTitle, "Sign in with Google")
    XCTAssertEqual(model.appleSignInButtonTitle, "Sign in with Apple")
    XCTAssertFalse(model.isAppleSignInEnabled)
  }

  func testSignInWithGoogleTracksSignInStartedEvent() async {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])

    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      $0.errorReporting.reportMessage = { _, _ in }
    } operation: {
      SignInPageModel()
    }
    // Short-circuit before the real Google SDK by returning no key window.
    model.keyWindowProvider = { nil }

    await model.signInWithGoogleButtonTapped()

    XCTAssertTrue(
      capturedEvents.value.contains {
        if case .signInStarted(let method) = $0 { return method == .google }
        return false
      })
  }

  func testSignInWithGooglePresentsAlertWhenNoKeyWindow() async {
    @Shared(.auth) var auth = Auth()
    let reportedMessages = LockIsolated<[String]>([])

    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportMessage = { msg, _ in
        reportedMessages.withValue { $0.append(msg) }
      }
    } operation: {
      SignInPageModel()
    }
    model.keyWindowProvider = { nil }

    await model.signInWithGoogleButtonTapped()

    expectNoDifference(model.presentedAlert, .signInError)
    XCTAssertEqual(reportedMessages.value.count, 1)
  }

  func testHandleSignInAPIFailureShowsNetworkAlertOnSSLError() async {
    @Shared(.auth) var auth = Auth()
    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
    } operation: {
      SignInPageModel()
    }

    let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
    let afError = AFError.sessionTaskFailed(error: underlying)

    await model.handleSignInAPIFailure(afError, authMethod: .google, step: "google_sign_in_flow")

    expectNoDifference(model.presentedAlert, .signInNetworkError)
  }

  func testHandleSignInAPIFailureShowsGenericAlertOnUnknownError() async {
    @Shared(.auth) var auth = Auth()
    let model = withDependencies {
      $0.analytics.track = { _ in }
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
    } operation: {
      SignInPageModel()
    }

    let genericError = NSError(domain: "com.google.GIDSignIn", code: -4)

    await model.handleSignInAPIFailure(genericError, authMethod: .google, step: "google_sign_in_flow")

    expectNoDifference(model.presentedAlert, .signInError)
  }

  func testHandleSignInAPIFailureTracksAndReportsWithTags() async {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
    let reportedTags = LockIsolated<[String: String]>([:])

    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      $0.errorReporting.reportErrorWithContext = { _, tags, _, _ in
        reportedTags.withValue { $0 = tags }
      }
    } operation: {
      SignInPageModel()
    }

    let genericError = NSError(domain: "com.google.GIDSignIn", code: -4)
    await model.handleSignInAPIFailure(genericError, authMethod: .google, step: "api_call")

    XCTAssertEqual(reportedTags.value["auth_method"], "google")
    XCTAssertEqual(reportedTags.value["error_domain"], "com.google.GIDSignIn")
    XCTAssertEqual(reportedTags.value["error_code"], "-4")
    XCTAssertTrue(
      capturedEvents.value.contains {
        if case .signInFailed(let method, _) = $0 { return method == .google }
        return false
      })
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL — `SignInPageModel` lacks the new members (`keyWindowProvider`, `signInWithGoogleButtonTapped`, `handleSignInAPIFailure`, display text, `isAppleSignInEnabled`).

- [ ] **Step 3: Replace the model in `Lengua/Views/Pages/SignInPage.swift`**

Replace the existing `SignInPageModel` (keep the `SignInPage` view stub for now — Task 5 rewrites it) with:

```swift
import Dependencies
@preconcurrency import GoogleSignIn
import GoogleSignInSwift
import Sharing
import SwiftUI

@MainActor
@Observable
final class SignInPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api
  @ObservationIgnored @Dependency(\.analytics) var analytics
  @ObservationIgnored @Dependency(\.errorReporting) var errorReporting

  // MARK: - Shared State
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var presentedAlert: LenguaAlert?
  let isAppleSignInEnabled = false

  var titleText: String { "Lengua" }
  var subtitleText: String { "Look it up. Keep it. Say it back." }
  var googleSignInButtonTitle: String { "Sign in with Google" }
  var appleSignInButtonTitle: String { "Sign in with Apple" }

  @ObservationIgnored
  var keyWindowProvider: @MainActor () -> UIViewController? = {
    UIApplication.shared.keyWindowPresentedController
  }

  // MARK: - User Actions

  func signInWithGoogleButtonTapped() async {
    await analytics.track(.signInStarted(method: .google))
    guard let presentingVC = keyWindowProvider() else {
      presentedAlert = .signInError
      await errorReporting.reportMessage(
        "Unable to present Google sign-in: no key window",
        ["auth_method": "google", "sign_in_step": "present_view_controller"])
      return
    }
    do {
      let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
      _ = try await signInResult.user.refreshTokensIfNeeded()
      guard let idToken = signInResult.user.idToken?.tokenString else {
        presentedAlert = .signInError
        await errorReporting.reportMessage(
          "Google sign-in missing idToken",
          ["auth_method": "google", "sign_in_step": "id_token"])
        return
      }
      let userId = signInResult.user.userID ?? "unknown"
      let result = try await api.signInViaGoogle(idToken)
      $auth.withLock { $0 = Auth(jwtToken: result.token, currentUser: result.user) }
      await analytics.track(.signInCompleted(method: .google, userId: userId))
    } catch {
      let nsError = error as NSError
      // Silently drop user-cancelled sign-ins (GIDSignInError.canceled = -5).
      if nsError.domain != kGIDSignInErrorDomain
        || nsError.code != GIDSignInError.canceled.rawValue
      {
        await handleSignInAPIFailure(error, authMethod: .google, step: "google_sign_in_flow")
      }
    }
  }

  // Apple sign-in is intentionally disabled for now (button rendered, no-op).
  func appleSignInButtonTapped() {}

  // MARK: - Internal Helpers

  // Internal so tests can drive alert/analytics/reporting routing directly.
  func handleSignInAPIFailure(_ error: Error, authMethod: AuthMethod, step: String) async {
    presentedAlert =
      NetworkErrorClassifier.isNetworkError(error) ? .signInNetworkError : .signInError
    await analytics.track(.signInFailed(method: authMethod, error: error.localizedDescription))
    let report = SignInErrorReport(error: error, authMethod: authMethod, step: step)
    await errorReporting.reportErrorWithContext(
      error, report.tags, report.contextKey, report.context)
  }
}
```

- [ ] **Step 4: Keep the stub view compiling (interim — real view lands in Task 5)**

The old stub `SignInPage` view still references the removed `signInButtonTitle` / `signInButtonTapped()`. In the same file, update those two references so the file builds; Task 5 replaces this view entirely:

```swift
      Button(model.googleSignInButtonTitle) {
        Task { await model.signInWithGoogleButtonTapped() }
      }
        .buttonStyle(.borderedProminent)
```

(Leave `@State var model`, the title, and subtitle lines as they are for now.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: PASS for all `SignInPageTests` cases; the app still compiles.

- [ ] **Step 6: Commit**

```bash
git add Lengua/Views/Pages/SignInPage.swift LenguaTests/SignInPageTests.swift
git commit -m "feat: implement SignInPageModel Google flow with tested failure routing"
```

---

### Task 5: Build the `SignInPage` view and wire app-level URL handling

**Files:**
- Modify: `Lengua/Views/Pages/SignInPage.swift` (view)
- Modify: `Lengua/Views/Pages/ContentView.swift` (store the model instance)
- Modify: `Lengua/LenguaApp.swift` (GoogleSignIn URL handling + restore)

**Interfaces:**
- Consumes: `SignInPageModel` (display text, `isAppleSignInEnabled`, `presentedAlert`, `signInWithGoogleButtonTapped()`), assets `"google-icon"` / `"LogoMark"`, `lenguaAlert(_:)`.

- [ ] **Step 1: Replace the `SignInPage` view in `Lengua/Views/Pages/SignInPage.swift`**

Replace the old `struct SignInPage` with:

```swift
struct SignInPage: View {
  @Bindable var model: SignInPageModel

  var body: some View {
    ZStack {
      Color(red: 0.24, green: 0.29, blue: 0.85)
        .ignoresSafeArea()

      VStack(spacing: 24) {
        Spacer()

        Image("LogoMark")
          .resizable()
          .scaledToFit()
          .frame(height: 96)

        Text(model.titleText)
          .font(.system(size: 56, weight: .bold))
          .foregroundStyle(.white)

        Text(model.subtitleText)
          .font(.title3)
          .foregroundStyle(.white.opacity(0.75))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 48)

        Spacer()

        VStack(spacing: 16) {
          WhiteSignInButton(
            iconImageName: "google-icon",
            systemIcon: nil,
            title: model.googleSignInButtonTitle
          ) {
            Task { await model.signInWithGoogleButtonTapped() }
          }

          WhiteSignInButton(
            iconImageName: nil,
            systemIcon: "apple.logo",
            title: model.appleSignInButtonTitle
          ) {
            model.appleSignInButtonTapped()
          }
          .disabled(!model.isAppleSignInEnabled)
          .opacity(model.isAppleSignInEnabled ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
    }
    .lenguaAlert($model.presentedAlert)
  }
}

private struct WhiteSignInButton: View {
  let iconImageName: String?
  let systemIcon: String?
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let iconImageName {
          Image(iconImageName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
        } else if let systemIcon {
          Image(systemName: systemIcon)
            .font(.system(size: 22))
            .foregroundStyle(.black)
        }
        Text(title)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.black)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }
}

#Preview {
  SignInPage(model: SignInPageModel())
}
```

- [ ] **Step 2: Store the model in `Lengua/Views/Pages/ContentView.swift`**

Change the `else` branch so the model is a stored property (needed for `@Bindable`):

```swift
@MainActor
struct ContentView: View {
  @Shared(.auth) var auth

  var mainContainerModel = MainContainerModel()
  var signInModel = SignInPageModel()

  var body: some View {
    Group {
      if auth.isLoggedIn {
        MainContainer(model: mainContainerModel)
      } else {
        SignInPage(model: signInModel)
      }
    }
  }
}
```

- [ ] **Step 3: Wire GoogleSignIn URL handling in `Lengua/LenguaApp.swift`**

Add `import GoogleSignIn` at the top, and attach modifiers to `ContentView()` in the `WindowGroup`:

```swift
        ContentView()
          .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
          }
          .onAppear {
            GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in }
          }
```

- [ ] **Step 4: Build and run the app to verify the sign-in screen renders**

Run: `make build`
Expected: compiles. Launch in the simulator; the sign-in screen shows the blue background, logo, title, subtitle, an enabled Google button, and a dimmed/disabled Apple button. (Full round-trip sign-in needs the simulator's Google account + the server running; visual verification is enough here.)

- [ ] **Step 5: Commit**

```bash
git add Lengua/Views/Pages/SignInPage.swift Lengua/Views/Pages/ContentView.swift Lengua/LenguaApp.swift
git commit -m "feat: build Sign-In page UI and wire GoogleSignIn URL handling"
```

---

### Task 6: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Format**

Run: `make format`
Then re-stage/commit only if files changed:
```bash
git add -A && git commit -m "style: apply swift-format" || echo "no formatting changes"
```

- [ ] **Step 2: Lint**

Run: `make lint`
Expected: no violations. Fix any and amend the relevant commit.

- [ ] **Step 3: Format check + full test suite**

Run: `make format-check && make test`
Expected: format-check passes; all tests green (existing + new `SignInPageTests`, `APIClientTests` decoding).

- [ ] **Step 4: Manual smoke (optional, needs server + Google account)**

With the Lengua server running (`~/code/lengua/server`, `local` config → `http://localhost:10020`) and a Google account in the simulator, tap **Sign in with Google**, complete the Google flow, and confirm the app transitions to `MainContainer` and `HomePage` greets the user by first name. If the server rejects the token, verify its `GOOGLE_CLIENT_ID` equals the iOS client ID above.

---

## Notes / follow-ups (out of scope)

- Apple sign-in implementation (button is disabled).
- Keychain migration for the JWT (`Auth.swift` TODO); still FileStorage-persisted.
- Real analytics provider (`AnalyticsClient.track` is a no-op).
- `LogoMark` is a placeholder cropped from the mockup — replace with real artwork.
- `displayName` / `role` server user fields are not stored on Lengua's `User`.
