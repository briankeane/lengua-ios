# Sign in with Apple (iOS client)

**Date:** 2026-08-01
**Status:** Approved — ready for implementation planning
**Scope:** iOS client only (this repo). Server endpoint is assumed, added separately.

## Goal

Turn the existing stubbed "Sign in with Apple" button in `SignInPage` into a
working sign-in that mirrors the flow in `~/playola/playola-radio-ios`, adapted
to Lengua's `{ user, token }` server contract (exactly as the already-shipped
Google port does).

## Context / current state

- `Lengua/Views/Pages/SignInPage.swift` already contains a full port of
  Playola's `SignInPage`. Google sign-in works end to end.
- The Apple button is deliberately stubbed: `let isAppleSignInEnabled = false`
  and `func appleSignInButtonTapped() {}` (no-op). The view renders a disabled
  custom white button.
- `AuthMethod.apple` and the `.signInError` / `.signInNetworkError` alert cases
  already exist and are reused by the Google path.
- Error routing (`handleSignInAPIFailure`, `SignInErrorReport`,
  `NetworkErrorClassifier`, `SignInAPIError`) already exists and is auth-method
  agnostic.

## Assumed server contract (not built here)

- `POST /v1/auth/apple`
- Request JSON body: `{ identityToken, authorizationCode, firstName, email?, lastName? }`
  - Optional fields (`email`, `lastName`) are omitted from the body when `nil`,
    matching Playola's parameter-building. Apple only returns name/email on the
    *first* authorization, so the client forwards whatever it receives.
- Response JSON body: `{ user, token }` — structurally identical to the existing
  `/v1/auth/google` response (`GoogleSignInResponse`).

The server team must implement this endpoint to match. This spec does not build
or modify the server (`~/code/lengua/server`). Three server-side requirements the
client depends on (out of scope here but noted for the server work):

- The server must key the account on the stable Apple subject (`sub`) inside the
  verified `identityToken`, **not** on email — Apple omits email/name on every
  sign-in after the first.
- When Apple omits name/email (all sign-ins after the first, where the client
  sends `firstName: ""` and no email/lastName), the server must **preserve** the
  previously stored profile fields rather than overwriting them with blanks, and
  must return a complete `User` in the response.
- **Replay protection is required.** The client sends no cryptographic nonce
  (Playola-faithful), so the server must not rely on `identityToken` signature
  validation alone. It must exchange the single-use `authorizationCode` with
  Apple's token endpoint (recommended — this is why the client forwards
  `authorizationCode`) or otherwise enforce a per-request nonce round-trip.
  Signature-only verification of the `identityToken` has no replay defense.

## Design

### 1. API layer — `Lengua/Core/API/APIClient.swift` + `APIClient+Live.swift`

Add a client method mirroring `signInViaGoogle`:

```swift
var signInViaApple: @Sendable (
  _ identityToken: String, _ email: String?, _ authorizationCode: String,
  _ firstName: String, _ lastName: String?
) async throws -> AppleSignInResult
```

- **Result type:** add a **parallel** `AppleSignInResult { user; token }` and
  `AppleSignInResponse` decoder, mirroring `GoogleSignInResult` /
  `GoogleSignInResponse`. Rationale: the shipped Google path stays 100%
  untouched (lowest risk); the small duplication is isolated. (Alternative
  considered: a shared `SignInResult` used by both — rejected to avoid
  rippling into the working Google model/tests.)
- **Live implementation:** mirrors `signInViaGoogle` — builds the parameter
  dictionary (omitting `nil` optionals), `POST`s with `JSONEncoding.default`,
  wraps failures in `SignInAPIError(authMethod: .apple, endpointPath:
  "/v1/auth/apple", ...)`, guards on `2xx`, decodes `AppleSignInResponse`.

### 2. Model — `SignInPageModel` (in `SignInPage.swift`)

Two deliberate improvements over a literal port (from Codex review): a
**testable decode seam** so the success path isn't buried behind an
unconstructible framework type, and **re-entrancy protection** around the async
completion (Lengua already guards the Google path this way).

- **Remove** `let isAppleSignInEnabled = false` and the no-op
  `appleSignInButtonTapped()`.

- **Add** `signInWithAppleButtonTapped(request: ASAuthorizationAppleIDRequest)`:
  sets `request.requestedScopes = [.email, .fullName]`; tracks
  `.signInStarted(method: .apple)`.

- **Add a decode seam** (testable without a real `ASAuthorization`):

  ```swift
  struct AppleSignInPayload: Equatable {
    let identityToken: String
    let authorizationCode: String
    let email: String?
    let firstName: String        // "" when Apple omits the name (post-first sign-in)
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

  func decodeAppleAuthorization(_ authorization: ASAuthorization) throws -> AppleSignInPayload
  ```

  `decodeAppleAuthorization` is the only thin, untestable glue (extracts bytes
  from `ASAuthorizationAppleIDCredential`); it throws the specific
  `AppleCredentialDecodeError` case so failures are diagnosable.

- **Add** `signInWithAppleCompleted(result: Result<ASAuthorization, any Error>) async`:
  - On `.success`: `do { let payload = try decodeAppleAuthorization(auth) }
    catch { present .signInError; reportMessage("...", ["auth_method": "apple",
    "sign_in_step": "credential_decode", "decode_reason":
    (error as? AppleCredentialDecodeError)?.rawValue ?? "unknown"]); return }`,
    then `await completeAppleSignIn(payload:)`.
  - On `.failure`: `await handleAppleAuthorizationFailure(error)`.

- **Add** `func completeAppleSignIn(_ payload: AppleSignInPayload) async` —
  **internal, fully unit-testable** (takes the plain payload, not the framework
  type):
  - Re-entrancy guard: `guard !isSigningIn else { return }; isSigningIn = true;
    defer { isSigningIn = false }` (reuses the existing flag — only one sign-in
    at a time across Google and Apple).
  - `do { let result = try await api.signInViaApple(payload.identityToken,
    payload.email, payload.authorizationCode, payload.firstName,
    payload.lastName); $auth.withLock { $0 = Auth(jwtToken: result.token,
    currentUser: result.user) }; await analytics.track(.signInCompleted(method:
    .apple, userId: payload.appleUserId)) }`
  - `catch { await handleSignInAPIFailure(error, authMethod: .apple, step:
    "api_call") }`

- **Add** private `handleAppleAuthorizationFailure(_ error:) async`:
  `ASAuthorizationError.canceled` → return silently; otherwise present
  `.signInError` and report with step `"authorization_failure"`.

- Analytics `userId` is `payload.appleUserId` (the Apple provider `sub`) — this
  is intentionally the **provider** id, consistent with the Google path which
  also tracks the provider `userID`, not the Lengua user id.
- Reuses existing `handleSignInAPIFailure`, `SignInErrorReport`,
  `NetworkErrorClassifier`, `AuthMethod.apple`, and alert cases — **no changes**
  to analytics, alerts, or error-reporting source.

### 3. View — `SignInPage` (in `SignInPage.swift`)

- Add `import AuthenticationServices`.
- Replace the Apple `WhiteSignInButton` with the native button:

```swift
SignInWithAppleButton(.signIn) { request in
  model.signInWithAppleButtonTapped(request: request)
} onCompletion: { result in
  Task { await model.signInWithAppleCompleted(result: result) }
}
.signInWithAppleButtonStyle(.white)
.frame(height: 56)
.clipShape(RoundedRectangle(cornerRadius: 12))
```

  placed with the same horizontal padding as the Google button so the two sit
  consistently, and `.disabled(model.isSigningIn)` / dimmed while a sign-in is in
  flight (matching the Google button).
- Remove the now-dead `appleSignInButtonTitle` property (the native button
  supplies its own label).
- Note: `SignInWithAppleButton` enforces Apple's own typography/logo, so it
  won't be pixel-identical to the custom `WhiteSignInButton`; verify the `.white`
  style has acceptable contrast on the blue background.

### 4. Project config — `project.yml` + new entitlement

- New file `Lengua/Lengua.entitlements`:

```xml
<key>com.apple.developer.applesignin</key>
<array><string>Default</string></array>
```

- Add `CODE_SIGN_ENTITLEMENTS: Lengua/Lengua.entitlements` to the `Lengua`
  target's base settings in `project.yml`. `make generate` regenerates the
  Xcode project.

**Prerequisite / risk (outside this repo's code):** adding the entitlement +
`CODE_SIGN_ENTITLEMENTS` is necessary but **not sufficient** for signed builds.
`DEVELOPMENT_TEAM` is currently `""`, and **both** bundle IDs —
`com.lengua-app.lengua` (Debug/Release) and `com.lengua-app.lengua.staging`
(Staging) — must have the "Sign In with Apple" capability enabled on their App
IDs in the Apple Developer portal. Compilation and unit tests pass without these,
but device/archive builds will fail to codesign until the team + portal
capabilities are configured. Flagged, not solved here.

### 5. Testing — `LenguaTests/SignInPageTests.swift` (swift-testing)

Mirror the existing suite's style (`@MainActor struct`, `expectNoDifference`,
`withDependencies`, `LockIsolated` for captures):

- `signInWithAppleButtonTapped` sets `requestedScopes == [.email, .fullName]`
  and tracks `.signInStarted(method: .apple)`. The request is constructible via
  `ASAuthorizationAppleIDProvider().createRequest()`.
- **`completeAppleSignIn(_:)` success** → stub `api.signInViaApple` to return a
  known `AppleSignInResult`; assert `@Shared(.auth)` becomes
  `Auth(jwtToken:currentUser:)` and `.signInCompleted(method: .apple, userId:)`
  is tracked with the payload's `appleUserId`. (This is the seam that makes the
  success path testable without a real `ASAuthorization`.)
- **`completeAppleSignIn(_:)` failure** → stub `api.signInViaApple` to throw;
  assert `.signInError` alert + `.signInFailed(method: .apple)` tracked +
  reported with `auth_method: "apple"`.
- **`completeAppleSignIn(_:)` re-entrancy** → with `isSigningIn = true`, calling
  it is a no-op (no API call, no auth write) — parallel to the existing Google
  re-entrancy test.
- `signInWithAppleCompleted(result: .failure(ASAuthorizationError(.canceled)))`
  → `presentedAlert` stays `nil` (silent cancel), nothing reported.
- `signInWithAppleCompleted(result: .failure(<non-cancel error>))` →
  `presentedAlert == .signInError` and one error reported.
- `handleSignInAPIFailure(..., authMethod: .apple, ...)` → network vs generic
  alert routing and `auth_method: "apple"` tag (parallel to the existing Google
  failure tests).
- Update `displayTextMatchesMockup`: drop the `isAppleSignInEnabled` and
  `appleSignInButtonTitle` assertions.

**Residual limitation:** only the thin `decodeAppleAuthorization(_:)` glue
remains uncovered, because `ASAuthorization` / `ASAuthorizationAppleIDCredential`
are not constructible in tests. All decision logic (decode-failure routing via
`AppleCredentialDecodeError`, API success/failure, auth persistence,
re-entrancy) is tested through the `AppleSignInPayload` seam. This is a strict
improvement over Playola, which left the entire success path untested.

## Out of scope (present in Playola, intentionally omitted)

- `revokeAppleCredentials` / any account-deletion revoke flow.
- `appRating.recordInstallDateIfNeeded()` — no `appRating` dependency in Lengua.
- Any server-side work.

## Success criteria

- `make generate && make build` succeeds; `make test` passes including the new
  Apple tests.
- `make lint` and `make format-check` clean.
- Tapping the Apple button presents the system Sign in with Apple sheet;
  completing it calls `POST /v1/auth/apple` and, on success, writes a logged-in
  `Auth` (JWT + user) to `@Shared(.auth)`.
- Cancel is silent; decode/API/network failures route to the correct alert and
  are reported with `auth_method: "apple"`.
