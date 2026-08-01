# Sign in with Apple Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **REQUIRED PER-TASK SKILLS (Lengua/CLAUDE.md):** before writing Swift in each task, invoke the relevant `pfw-*` skills. This plan touches: `pfw-dependencies` (APIClient/@DependencyClient, `withDependencies`), `pfw-observable-models` (SignInPageModel), `pfw-sharing` (`@Shared(.auth)` write-path testing), `pfw-testing` + `pfw-custom-dump` (swift-testing, `expectNoDifference`, `withMainSerialExecutor`), `pfw-modern-swiftui` (the view). Never use XCTest; never use `Task.sleep` in tests.

**Goal:** Turn the stubbed "Sign in with Apple" button in `SignInPage` into a working sign-in that mirrors the Playola flow, adapted to Lengua's `{ user, token }` server contract.

**Architecture:** Follows the shipped Google sign-in exactly. A new `api.signInViaApple` client method posts the Apple credential to an assumed `POST /v1/auth/apple` and returns `{ user, token }`. The model decodes the `ASAuthorization` through a testable `AppleSignInPayload` seam, then persists `Auth(jwtToken:currentUser:)` to `@Shared(.auth)`. The view uses Apple's native `SignInWithAppleButton`.

**Tech Stack:** Swift, SwiftUI, AuthenticationServices, Alamofire, Point-Free `swift-dependencies` / `swift-sharing` / `swift-custom-dump`, swift-testing, XcodeGen.

## Global Constraints

- **Framework:** swift-testing only (`import Testing`, `@Test`, `#expect`/`#require`). Never XCTest.
- **Value assertions:** use `expectNoDifference` / `expectDifference` from CustomDump, not raw `#expect(a == b)`.
- **No `Task.sleep` in tests.** Use `withMainSerialExecutor` (ConcurrencyExtras) to flush fire-and-forget `Task {}` work deterministically.
- **Test naming:** camelCase, no `test` prefix, no underscores.
- **Suites:** `struct`, `@MainActor`. This suite touches process-global `@Shared(.auth)` → mark it `.serialized`.
- **Assumed server contract (client depends on it):** `POST /v1/auth/apple`, body `{ identityToken, authorizationCode, firstName, email?, lastName? }` (nil optionals omitted), response `{ user, token }`.
- **Model owns all text/logic; the View only renders** (Lengua MV architecture).
- **Build/test target the iOS 18 simulator** with `CODE_SIGNING_ALLOWED=NO` (`make build`, `make test`), so the new entitlement does not block CI builds. Device/archive signing is an out-of-band portal prerequisite.

---

### Task 1: API layer — `signInViaApple` + result/response types + live implementation

Mirror the existing `signInViaGoogle` in `APIClient.swift:16` / `APIClient+Live.swift:24`.

**Files:**
- Modify: `Lengua/Core/API/APIClient.swift` (add types after `GoogleSignInResponse`, ~line 49; add client property near `signInViaGoogle`, line 16)
- Modify: `Lengua/Core/API/APIClient+Live.swift` (add closure alongside `signInViaGoogle`, ~line 24)
- Test: `LenguaTests/APIClientTests.swift` (add a decode test next to `googleSignInResponseDecodesUserAndToken`)

**Interfaces:**
- Consumes: existing `User`, `SignInAPIError`, `APIError`, `AuthMethod`.
- Produces:
  ```swift
  struct AppleSignInResult: Equatable, Sendable { let user: User; let token: String }
  // On APIClient:
  var signInViaApple: @Sendable (
    _ identityToken: String, _ email: String?, _ authorizationCode: String,
    _ firstName: String, _ lastName: String?
  ) async throws -> AppleSignInResult
  ```

- [ ] **Step 1: Invoke `pfw-dependencies` and `pfw-testing`/`pfw-custom-dump` skills.**

- [ ] **Step 2: Write the failing decode test** in `LenguaTests/APIClientTests.swift`:

```swift
@Test func appleSignInResponseDecodesUserAndToken() throws {
  let json = Data(
    """
    {
      "user": {
        "id": "apple-u1",
        "firstName": "Sam",
        "lastName": "Lee",
        "displayName": "Sam Lee",
        "email": "sam@example.com",
        "profileImageUrl": "https://img/1.png",
        "role": "user"
      },
      "token": "jwt-apple-123"
    }
    """.utf8)

  let decoded = try JSONDecoder().decode(AppleSignInResponse.self, from: json)

  expectNoDifference(decoded.token, "jwt-apple-123")
  expectNoDifference(decoded.result.user.id, "apple-u1")
  expectNoDifference(decoded.result.user.email, "sam@example.com")
  expectNoDifference(decoded.result.user.firstName, "Sam")
  expectNoDifference(decoded.result.token, "jwt-apple-123")
}
```

- [ ] **Step 3: Run the test, verify it fails to compile** (`AppleSignInResponse` undefined)

Run: `make test`
Expected: build failure — cannot find `AppleSignInResponse` in scope.

- [ ] **Step 4: Add the result + response types** in `APIClient.swift`, immediately after the `GoogleSignInResponse` struct (mirrors it exactly):

```swift
struct AppleSignInResult: Equatable, Sendable {
  let user: User
  let token: String
}

/// Decodes the `POST /v1/auth/apple` response `{ user, token }`.
/// Extra server fields (`displayName`, `role`) are intentionally ignored.
struct AppleSignInResponse: Decodable {
  struct APIUser: Decodable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
  }
  let user: APIUser
  let token: String

  var result: AppleSignInResult {
    AppleSignInResult(
      user: User(
        id: user.id, email: user.email, firstName: user.firstName,
        lastName: user.lastName, profileImageUrl: user.profileImageUrl),
      token: token)
  }
}
```

- [ ] **Step 5: Add the client property** in `APIClient.swift`, directly after the `signInViaGoogle` declaration (line 16):

```swift
  /// Exchanges an Apple identity token + auth code for a Lengua session (JWT + user).
  /// Apple returns name/email only on the first authorization; the client forwards
  /// whatever it receives. `email` and `lastName` are omitted from the body when nil.
  var signInViaApple: @Sendable (
    _ identityToken: String, _ email: String?, _ authorizationCode: String,
    _ firstName: String, _ lastName: String?
  ) async throws -> AppleSignInResult
```

- [ ] **Step 6: Run the decode test, verify it passes**

Run: `make test`
Expected: `appleSignInResponseDecodesUserAndToken` passes (build now also fails elsewhere only if the live closure is missing — see Step 7; add it in the same edit before re-running if the `@DependencyClient` macro requires the closure in `liveValue`).

- [ ] **Step 7: Add the live closure** in `APIClient+Live.swift`, immediately after the `signInViaGoogle` closure (before `saveVocabItem`, ~line 59). Mirrors `signInViaGoogle`'s error/status/decoding handling:

```swift
      signInViaApple: { identityToken, email, authorizationCode, firstName, lastName in
        let path = "v1/auth/apple"
        let url = baseUrl.appendingPathComponent(path)
        var parameters: [String: Any] = [
          "identityToken": identityToken,
          "authorizationCode": authorizationCode,
          "firstName": firstName,
        ]
        if let email { parameters["email"] = email }
        if let lastName { parameters["lastName"] = lastName }

        let response = await session.request(
          url,
          method: .post,
          parameters: parameters,
          encoding: JSONEncoding.default
        ).serializingData().response

        guard let httpResponse = response.response else {
          throw SignInAPIError(
            authMethod: .apple, endpointPath: "/\(path)", statusCode: nil,
            responseBody: nil, underlyingError: response.error ?? APIError.dataNotValid)
        }

        let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
        guard (200..<300).contains(httpResponse.statusCode) else {
          throw SignInAPIError(
            authMethod: .apple, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: response.error ?? APIError.dataNotValid)
        }

        guard let data = response.data,
          let decoded = try? JSONDecoder().decode(AppleSignInResponse.self, from: data)
        else {
          throw SignInAPIError(
            authMethod: .apple, endpointPath: "/\(path)",
            statusCode: httpResponse.statusCode, responseBody: body,
            underlyingError: APIError.dataNotValid)
        }

        return decoded.result
      },
```

- [ ] **Step 8: Run the full suite + lint/format**

Run: `make test && make lint && make format-check`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add Lengua/Core/API/APIClient.swift Lengua/Core/API/APIClient+Live.swift LenguaTests/APIClientTests.swift
git commit -m "feat: add signInViaApple API client method"
```

---

### Task 2: Model — decode seam, completion, re-entrancy (with tests)

Adds the Apple sign-in logic to `SignInPageModel`. Leaves the old stub properties (`isAppleSignInEnabled`, `appleSignInButtonTitle`, `appleSignInButtonTapped()`) in place so the view still compiles — they are removed in Task 3. All new logic is unit-tested through the `AppleSignInPayload` seam.

**Files:**
- Modify: `Lengua/Views/Pages/SignInPage.swift` (add `import AuthenticationServices`; add types + methods to the model)
- Modify: `LenguaTests/SignInPageTests.swift` (add `import AuthenticationServices`; mark suite `.serialized`; add tests)

**Interfaces:**
- Consumes: `api.signInViaApple`, `AppleSignInResult` (Task 1); existing `handleSignInAPIFailure`, `SignInErrorReport`, `NetworkErrorClassifier`, `AuthMethod.apple`, `LenguaAlert.signInError`, `isSigningIn`, `@Shared(.auth)`, `analytics`, `errorReporting`.
- Produces:
  ```swift
  struct AppleSignInPayload: Equatable {
    let identityToken: String; let authorizationCode: String
    let email: String?; let firstName: String; let lastName: String?
    let appleUserId: String
  }
  enum AppleCredentialDecodeError: String, Error {
    case notAppleIDCredential, missingIdentityToken, identityTokenNotUTF8
    case missingAuthorizationCode, authorizationCodeNotUTF8
  }
  // On SignInPageModel:
  func signInWithAppleButtonTapped(request: ASAuthorizationAppleIDRequest)
  func signInWithAppleCompleted(result: Result<ASAuthorization, any Error>) async
  func completeAppleSignIn(_ payload: AppleSignInPayload) async
  func decodeAppleAuthorization(_ authorization: ASAuthorization) throws -> AppleSignInPayload
  ```

- [ ] **Step 1: Invoke `pfw-observable-models`, `pfw-dependencies`, `pfw-sharing`, `pfw-testing`, `pfw-custom-dump` skills.**

- [ ] **Step 2: Mark the test suite `.serialized`** in `LenguaTests/SignInPageTests.swift` and add the import. Change the suite declaration:

```swift
import AuthenticationServices   // add near the other imports
...
@Suite(.serialized)
@MainActor
struct SignInPageTests {
```

- [ ] **Step 3: Write the failing tests** in `SignInPageTests.swift` (append inside the suite). These reference symbols added in Steps 5–6:

```swift
@Test func signInWithAppleSetsScopesAndTracksStarted() async {
  await withMainSerialExecutor {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
    let model = withDependencies {
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
    } operation: {
      SignInPageModel()
    }

    let request = ASAuthorizationAppleIDProvider().createRequest()
    model.signInWithAppleButtonTapped(request: request)

    expectNoDifference(request.requestedScopes, [.email, .fullName])
    await Task.yield()
    #expect(
      capturedEvents.value.contains {
        if case .signInStarted(let method) = $0 { return method == .apple }
        return false
      })
  }
}

@Test func completeAppleSignInStoresAuthAndTracksCompletedOnSuccess() async {
  await withDependencies {
    $0.defaultFileStorage = .inMemory
  } operation: {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])
    let user = User(
      id: "apple-user-1", email: "sam@example.com", firstName: "Sam",
      lastName: "Lee", profileImageUrl: nil)

    let model = withDependencies {
      $0.api.signInViaApple = { _, _, _, _, _ in
        AppleSignInResult(user: user, token: "jwt-abc")
      }
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
    } operation: {
      SignInPageModel()
    }

    let payload = AppleSignInPayload(
      identityToken: "id-token", authorizationCode: "auth-code",
      email: "sam@example.com", firstName: "Sam", lastName: "Lee",
      appleUserId: "apple-user-1")

    await model.completeAppleSignIn(payload)

    expectNoDifference(model.auth, Auth(jwtToken: "jwt-abc", currentUser: user))
    #expect(
      capturedEvents.value.contains {
        if case .signInCompleted(let method, let userId) = $0 {
          return method == .apple && userId == "apple-user-1"
        }
        return false
      })
  }
}

@Test func completeAppleSignInShowsAlertAndTracksFailureOnAPIError() async {
  await withDependencies {
    $0.defaultFileStorage = .inMemory
  } operation: {
    @Shared(.auth) var auth = Auth()
    let capturedEvents = LockIsolated<[AnalyticsEvent]>([])

    let model = withDependencies {
      $0.api.signInViaApple = { _, _, _, _, _ in
        throw NSError(domain: "com.lengua.api", code: 500)
      }
      $0.analytics.track = { event in capturedEvents.withValue { $0.append(event) } }
      $0.errorReporting.reportErrorWithContext = { _, _, _, _ in }
    } operation: {
      SignInPageModel()
    }

    let payload = AppleSignInPayload(
      identityToken: "id-token", authorizationCode: "auth-code",
      email: nil, firstName: "", lastName: nil, appleUserId: "apple-user-2")

    await model.completeAppleSignIn(payload)

    expectNoDifference(model.presentedAlert, .signInError)
    expectNoDifference(model.auth.isLoggedIn, false)
    #expect(
      capturedEvents.value.contains {
        if case .signInFailed(let method, _) = $0 { return method == .apple }
        return false
      })
  }
}

@Test func completeAppleSignInIgnoredWhileAlreadySigningIn() async {
  await withDependencies {
    $0.defaultFileStorage = .inMemory
  } operation: {
    @Shared(.auth) var auth = Auth()
    let apiCalled = LockIsolated(false)

    let model = withDependencies {
      $0.api.signInViaApple = { _, _, _, _, _ in
        apiCalled.setValue(true)
        return AppleSignInResult(
          user: User(id: "x", email: "x@x.com", firstName: nil, lastName: nil, profileImageUrl: nil),
          token: "t")
      }
    } operation: {
      SignInPageModel()
    }
    model.isSigningIn = true

    let payload = AppleSignInPayload(
      identityToken: "id-token", authorizationCode: "auth-code",
      email: nil, firstName: "", lastName: nil, appleUserId: "apple-user-3")

    await model.completeAppleSignIn(payload)

    #expect(apiCalled.value == false)
    expectNoDifference(model.auth.isLoggedIn, false)
  }
}

@Test func signInWithAppleCompletedCancelledFailureIsSilent() async {
  @Shared(.auth) var auth = Auth()
  let reportCount = LockIsolated(0)

  let model = withDependencies {
    $0.errorReporting.reportErrorWithContext = { _, _, _, _ in
      reportCount.withValue { $0 += 1 }
    }
  } operation: {
    SignInPageModel()
  }

  let cancelled = ASAuthorizationError(.canceled)
  await model.signInWithAppleCompleted(result: .failure(cancelled))

  expectNoDifference(model.presentedAlert, nil)
  expectNoDifference(reportCount.value, 0)
}

@Test func signInWithAppleCompletedNonCancelFailureShowsAlertAndReports() async {
  @Shared(.auth) var auth = Auth()
  let reportCount = LockIsolated(0)

  let model = withDependencies {
    $0.errorReporting.reportErrorWithContext = { _, _, _, _ in
      reportCount.withValue { $0 += 1 }
    }
  } operation: {
    SignInPageModel()
  }

  let failed = ASAuthorizationError(.failed)
  await model.signInWithAppleCompleted(result: .failure(failed))

  expectNoDifference(model.presentedAlert, .signInError)
  expectNoDifference(reportCount.value, 1)
}
```

- [ ] **Step 4: Run the tests, verify they fail to compile** (new symbols undefined)

Run: `make test`
Expected: build failure — `AppleSignInPayload`, `completeAppleSignIn`, etc. not found.

- [ ] **Step 5: Add `import AuthenticationServices`** at the top of `Lengua/Views/Pages/SignInPage.swift`, then add the seam types at file scope (below the model class, above the `SignInPage` view struct):

```swift
struct AppleSignInPayload: Equatable {
  let identityToken: String
  let authorizationCode: String
  let email: String?
  let firstName: String
  let lastName: String?
  let appleUserId: String
}

enum AppleCredentialDecodeError: String, Error {
  case notAppleIDCredential
  case missingIdentityToken
  case identityTokenNotUTF8
  case missingAuthorizationCode
  case authorizationCodeNotUTF8
}
```

- [ ] **Step 6: Add the model methods.** In `SignInPageModel`, under `// MARK: - User Actions` (after `signInWithGoogleButtonTapped`), add:

```swift
  func signInWithAppleButtonTapped(request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.email, .fullName]
    Task { await analytics.track(.signInStarted(method: .apple)) }
  }

  func signInWithAppleCompleted(result: Result<ASAuthorization, any Error>) async {
    switch result {
    case .success(let authorization):
      let payload: AppleSignInPayload
      do {
        payload = try decodeAppleAuthorization(authorization)
      } catch {
        presentedAlert = .signInError
        await errorReporting.reportMessage(
          "Error decoding sign-in info from Apple",
          [
            "auth_method": "apple",
            "sign_in_step": "credential_decode",
            "decode_reason": (error as? AppleCredentialDecodeError)?.rawValue ?? "unknown",
          ])
        return
      }
      await completeAppleSignIn(payload)
    case .failure(let error):
      await handleAppleAuthorizationFailure(error)
    }
  }

  func completeAppleSignIn(_ payload: AppleSignInPayload) async {
    // Only one sign-in at a time across Google and Apple.
    guard !isSigningIn else { return }
    isSigningIn = true
    defer { isSigningIn = false }

    do {
      let result = try await api.signInViaApple(
        payload.identityToken, payload.email, payload.authorizationCode,
        payload.firstName, payload.lastName)
      $auth.withLock { $0 = Auth(jwtToken: result.token, currentUser: result.user) }
      await analytics.track(.signInCompleted(method: .apple, userId: payload.appleUserId))
    } catch {
      await handleSignInAPIFailure(error, authMethod: .apple, step: "api_call")
    }
  }
```

Then, under `// MARK: - Internal Helpers` (near `handleSignInAPIFailure`), add the decode seam as internal so it can be covered later, and a private authorization-failure handler:

```swift
  // Thin extraction of the Apple credential. The only piece not unit-tested,
  // because ASAuthorization / ASAuthorizationAppleIDCredential cannot be
  // constructed in tests. Throws a specific case so decode failures are
  // diagnosable in error reports.
  func decodeAppleAuthorization(_ authorization: ASAuthorization) throws -> AppleSignInPayload {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      throw AppleCredentialDecodeError.notAppleIDCredential
    }
    guard let identityTokenData = credential.identityToken else {
      throw AppleCredentialDecodeError.missingIdentityToken
    }
    guard let identityToken = String(data: identityTokenData, encoding: .utf8) else {
      throw AppleCredentialDecodeError.identityTokenNotUTF8
    }
    guard let authCodeData = credential.authorizationCode else {
      throw AppleCredentialDecodeError.missingAuthorizationCode
    }
    guard let authorizationCode = String(data: authCodeData, encoding: .utf8) else {
      throw AppleCredentialDecodeError.authorizationCodeNotUTF8
    }
    return AppleSignInPayload(
      identityToken: identityToken,
      authorizationCode: authorizationCode,
      email: credential.email,
      firstName: credential.fullName?.givenName ?? "",
      lastName: credential.fullName?.familyName,
      appleUserId: credential.user)
  }
```

Under `// MARK: - Private Helpers`, add:

```swift
  private func handleAppleAuthorizationFailure(_ error: any Error) async {
    // The user tapping "Cancel" on the system sheet is not an error.
    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      return
    }
    presentedAlert = .signInError
    let report = SignInErrorReport(error: error, authMethod: .apple, step: "authorization_failure")
    await errorReporting.reportErrorWithContext(
      error, report.tags, report.contextKey, report.context)
  }
```

- [ ] **Step 7: Run the tests, verify they pass**

Run: `make test`
Expected: all six new tests pass; existing tests still pass.

- [ ] **Step 8: Lint + format**

Run: `make lint && make format-check`
Expected: pass.

- [ ] **Step 9: Commit**

```bash
git add Lengua/Views/Pages/SignInPage.swift LenguaTests/SignInPageTests.swift
git commit -m "feat: add Apple sign-in logic to SignInPageModel"
```

---

### Task 3: View — native Apple button + remove stub properties

Swap the disabled custom Apple button for Apple's native `SignInWithAppleButton`, wired to the Task 2 model methods, and delete the now-dead stub properties.

**Files:**
- Modify: `Lengua/Views/Pages/SignInPage.swift` (model: delete stub props; view: swap the button)
- Modify: `LenguaTests/SignInPageTests.swift` (update `displayTextMatchesMockup`)

**Interfaces:**
- Consumes: `model.signInWithAppleButtonTapped(request:)`, `model.signInWithAppleCompleted(result:)`, `model.isSigningIn` (Task 2).
- Produces: nothing new (removes `isAppleSignInEnabled`, `appleSignInButtonTitle`, `appleSignInButtonTapped()`).

- [ ] **Step 1: Invoke `pfw-modern-swiftui` and `pfw-observable-models` skills.**

- [ ] **Step 2: Update the failing test first** — edit `displayTextMatchesMockup` in `SignInPageTests.swift` to drop the two assertions that reference the properties being deleted:

```swift
@Test func displayTextMatchesMockup() {
  @Shared(.auth) var auth = Auth()
  let model = SignInPageModel()
  expectNoDifference(model.titleText, "Lengua")
  expectNoDifference(model.subtitleText, "Look it up. Keep it. Say it back.")
  expectNoDifference(model.googleSignInButtonTitle, "Sign in with Google")
}
```

- [ ] **Step 3: Delete the stub model properties.** In `SignInPageModel`, remove these three members:
  - `let isAppleSignInEnabled = false`
  - `var appleSignInButtonTitle: String { "Sign in with Apple" }`
  - `func appleSignInButtonTapped() {}`

- [ ] **Step 4: Swap the view button.** In the `SignInPage` view's auth-button `VStack`, replace the Apple `WhiteSignInButton { ... }` block (the one using `systemIcon: "apple.logo"` / `model.appleSignInButtonTapped()`) with the native button:

```swift
SignInWithAppleButton(.signIn) { request in
  model.signInWithAppleButtonTapped(request: request)
} onCompletion: { result in
  Task { await model.signInWithAppleCompleted(result: result) }
}
.signInWithAppleButtonStyle(.white)
.frame(height: 56)
.clipShape(RoundedRectangle(cornerRadius: 12))
.disabled(model.isSigningIn)
.opacity(model.isSigningIn ? 0.5 : 1)
```

Keep it inside the same `VStack(spacing: 16)` right after the Google `WhiteSignInButton`, so both buttons share the `.padding(.horizontal, 24)` already applied to the stack.

- [ ] **Step 5: Verify the build compiles and all tests pass**

Run: `make test`
Expected: build succeeds (no remaining references to the deleted properties); all tests pass.

- [ ] **Step 6: Lint + format**

Run: `make lint && make format-check`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Lengua/Views/Pages/SignInPage.swift LenguaTests/SignInPageTests.swift
git commit -m "feat: render native Sign in with Apple button"
```

---

### Task 4: Project config — Sign in with Apple entitlement

Add the entitlement and wire it in `project.yml`. Simulator builds (`CODE_SIGNING_ALLOWED=NO`) are unaffected; device/archive signing needs the portal + team, which is called out as a prerequisite.

**Files:**
- Create: `Lengua/Lengua.entitlements`
- Modify: `project.yml` (`targets.Lengua.settings.base`)

**Interfaces:**
- Consumes: nothing. Produces: nothing (build configuration only).

- [ ] **Step 1: Invoke `pfw-spm` skill** (XcodeGen/project-config context).

- [ ] **Step 2: Create `Lengua/Lengua.entitlements`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Wire the entitlement in `project.yml`.** Under `targets.Lengua.settings.base`, add (alongside `INFOPLIST_FILE`):

```yaml
        CODE_SIGN_ENTITLEMENTS: Lengua/Lengua.entitlements
```

- [ ] **Step 4: Regenerate and build**

Run: `make generate && make build`
Expected: project regenerates with the entitlement wired; simulator build succeeds (entitlement not enforced under `CODE_SIGNING_ALLOWED=NO`).

- [ ] **Step 5: Run the full suite + lint/format**

Run: `make test && make lint && make format-check`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Lengua/Lengua.entitlements project.yml
git commit -m "chore: add Sign in with Apple entitlement"
```

- [ ] **Step 7: Record the signing prerequisite.** Note in the PR description that before a signed device/TestFlight build works, both App IDs (`com.lengua-app.lengua`, `com.lengua-app.lengua.staging`) need "Sign In with Apple" enabled in the Apple Developer portal and `DEVELOPMENT_TEAM` must be set. This is out of band and cannot be done from the repo.

---

## Post-implementation (per Lengua/CLAUDE.md pipeline)

After all four tasks: run Codex adversarial review (`/codex review` then `/codex challenge`) on the final diff before opening the PR. Fix anything surfaced; re-run if fixes are non-trivial.

## Self-Review notes

- **Spec coverage:** API (§1) → Task 1. Model seam/completion/re-entrancy (§2) → Task 2. View/native button (§3) → Task 3. Entitlement/config (§4) → Task 4. Testing (§5) → Tasks 1–3. Server-contract requirements are documented in the spec; no client task (iOS-only scope).
- **Untested-by-design:** `decodeAppleAuthorization` glue (ASAuthorization not constructible) — every decision path around it is tested via `AppleSignInPayload`.
- **Type consistency:** `AppleSignInResult` (Task 1) is the return of `api.signInViaApple` consumed in Task 2's `completeAppleSignIn`; `AppleSignInPayload` fields match between the seam type, `decodeAppleAuthorization`, and all Task 2 tests; `signInWithAppleButtonTapped` / `signInWithAppleCompleted` names match Task 3's view wiring.
