# Google Sign-In — Design Spec

**Date:** 2026-07-30
**Branch:** `briankeane/google-signin`
**Status:** Approved (design), pending implementation

## Goal

Replace the placeholder `SignInPage` with a working **Sign in with Google** flow,
laid out to match the approved mockup (blue background, Lengua logo mark,
"Lengua" title, "Look it up. Keep it. Say it back." subtitle, Google + Apple
buttons). Google is fully functional; the Apple button is present but visually
disabled (scope A). Code is ported/adapted from `~/playola/playola-radio-ios`.

## Success criteria

- Tapping **Sign in with Google** runs the Google SDK flow, exchanges the
  resulting **idToken** with the Lengua server, and on success sets
  `@Shared(.auth)` so `ContentView` flips to `MainContainer`.
- User-cancelled Google sign-in is silently ignored (no error alert, no
  `signInFailed` analytics).
- API/network failures present the correct alert (`.signInError` vs
  `.signInNetworkError`), fire a `signInFailed` analytics event, and report to
  Sentry with structured tags/context.
- The **Apple** button renders per the mockup but is disabled (no-op).
- Tests pass via `make test` (app-hosted `LenguaTests`).

## Server contract (verified in `~/code/lengua/server`)

- `POST /v1/auth/google`, body `{ "idToken": "<google id token>" }`
  (route: `src/api/auth/index.ts`; validated via `checkBodyFor(['idToken'])`).
- **200** response: `{ "user": { id, firstName, lastName, displayName, email,
  profileImageUrl, role }, "token": "<jwt>" }`.
- Server verifies the idToken's `audience` against `GOOGLE_CLIENT_ID`
  (`src/lib/auth/auth.lib.ts`). The iOS `GIDClientID` and the server's
  `GOOGLE_CLIENT_ID` must be the **same** iOS OAuth client ID for verification
  to pass. **(Confirm before live testing.)**

This differs from Playola, which sent a **serverAuthCode** to
`/v1/auth/google/signin`. We send an **idToken** and consume a richer
`{ user, token }` response, so the API method and response mapping are adapted,
not copied verbatim.

## Auth / config decisions

- **Google client ID**: hardcoded directly in `Info.plist` (Playola style). An
  iOS OAuth **client ID** ships in every copy of the app and is not a secret;
  it does not go through the gitignored `Secrets-*.xcconfig` mechanism (that
  holds `DEV_ENVIRONMENT` / `SENTRY_DSN`). We use `GIDClientID` +
  reversed-client-ID URL scheme only. `GIDServerClientID` is **not** needed
  (that is for the serverAuthCode flow we are not using).
- Support email in alert copy: **lonesomewhistle@gmail.com**.
- **Keychain**: out of scope. JWT continues to persist via `@Shared(.auth)`
  FileStorage (the existing `Auth.swift` TODO stays).

## New files (ported/adapted from Playola)

1. **`Lengua/Extensions/UIApplication+keyWindow.swift`** — verbatim port.
   Provides `keyWindowPresentedController` used as the Google presenter VC.
2. **`Lengua/Core/Analytics/AnalyticsEvent.swift`** — minimal new enum:
   `signInStarted(method:)`, `signInCompleted(method:userId:)`,
   `signInFailed(method:error:)`, plus `enum AuthMethod: String { apple, google }`.
   (NOT Playola's 330-line event set — YAGNI.)
3. **`Lengua/Core/ErrorReporting/ErrorReportingClient.swift`** — port:
   - `@DependencyClient ErrorReportingClient` (`reportError`,
     `reportErrorWithContext`, `reportMessage`) with live Sentry impl +
     `.noop` test value, registered at `\.errorReporting`.
   - `SignInAPIError` (carries authMethod, endpointPath, statusCode,
     responseBody, underlyingError).
   - `NetworkErrorClassifier` (network-error code set + `isNetworkError` +
     `errorTags`).
   - `SignInErrorReport` (builds Sentry tags/context, redacts token-bearing
     response fields).

   The existing static `ErrorReporting.start()` (Sentry init in `AppDelegate`)
   is unchanged; the client is complementary.

## Edited files

4. **`Lengua/Core/Analytics/AnalyticsClient.swift`** — add
   `var track: @Sendable (_ event: AnalyticsEvent) async -> Void`
   (live + test no-op until a real provider exists). Keep `initialize`.
5. **`Lengua/Core/API/APIClient.swift`** — add
   `var signInViaGoogle: @Sendable (_ idToken: String) async throws -> GoogleSignInResult`
   where `GoogleSignInResult` carries the mapped `User` + `token` string.
6. **`Lengua/Core/API/APIClient+Live.swift`** — implement `signInViaGoogle`:
   POST `{ idToken }` to `/v1/auth/google`, decode `{ user, token }` into a DTO,
   map to Lengua `User(id, email, firstName, lastName, profileImageUrl)`
   (ignore server `displayName`/`role` for now). On non-2xx, throw
   `SignInAPIError` with statusCode/responseBody for Sentry context.
7. **`Lengua/Views/Reusable Components/LenguaAlert.swift`** — add static
   factories `LenguaAlert.signInError` and `LenguaAlert.signInNetworkError`
   (copy adapted for Lengua; support email `lonesomewhistle@gmail.com`).
8. **`Lengua/Views/Pages/SignInPage.swift`** — rewrite both types:
   - **`SignInPageModel`** (`@MainActor @Observable`, `ViewModel` base):
     - Deps: `\.api`, `\.analytics`, `\.errorReporting`; `@Shared(.auth)`.
     - Injectable `keyWindowProvider: @MainActor () -> UIViewController?`.
     - Display text: `titleText` "Lengua", `subtitleText`
       "Look it up. Keep it. Say it back.", `googleSignInButtonTitle`
       "Sign in with Google", `appleSignInButtonTitle` "Sign in with Apple",
       `isAppleSignInEnabled = false`.
     - `presentedAlert: LenguaAlert?`.
     - `signInWithGoogleButtonTapped() async`: track `signInStarted(.google)`;
       guard key window (else `.signInError` + `reportMessage`); run
       `GIDSignIn.sharedInstance.signIn(withPresenting:)`; `refreshTokensIfNeeded`;
       read `idToken.tokenString` (guard missing → `.signInError` +
       `reportMessage`); `api.signInViaGoogle(idToken)`; set
       `Auth(jwtToken: token, currentUser: user)`; track
       `signInCompleted(.google, userId:)`. Swallow `GIDSignInError.canceled`;
       otherwise route through `handleSignInAPIFailure`.
     - `handleSignInAPIFailure(_:authMethod:step:)` (internal, tested): pick
       alert via `NetworkErrorClassifier`, track `signInFailed`, report via
       `SignInErrorReport`.
     - `appleSignInButtonTapped()`: no-op (disabled).
   - **`SignInPage`** view: blue background, `LogoMark` image, title, subtitle,
     `Spacer`, `CustomGoogleSignInButton` (white, `google-icon` + title, calls
     model), disabled Apple button (`isAppleSignInEnabled` → opacity/disabled),
     `.lenguaAlert($model.presentedAlert)`.
9. **`Lengua/LenguaApp.swift`** — on the `ContentView` in `WindowGroup`:
   `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }` and
   `.onAppear { GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in } }`.
   `import GoogleSignIn`.
10. **`project.yml`** — add package `GoogleSignIn`
    (`https://github.com/google/GoogleSignIn-iOS`, from a current major, e.g.
    `8.0.0`), products `GoogleSignIn` + `GoogleSignInSwift`, to the `Lengua`
    target. Regenerate the Xcode project (`make generate` / `xcodegen`).
11. **`Lengua/Info.plist`** — add `GIDClientID` (the iOS OAuth client ID) and a
    `CFBundleURLTypes` entry whose scheme is the reversed client ID. Values
    supplied at implementation time.

## Assets

- **`google-icon.imageset`** — copy from Playola's asset catalog into
  `Lengua/Assets.xcassets/`.
- **`LogoMark.imageset`** — Lengua's own logo mark (the mockup's cup/¿? mark).
  The repo's `AppIcon.appiconset` is an empty placeholder (no PNG), and
  Playola's `LogoMark` is Playola's logo (not reusable). **Asset gap:** need
  Lengua logo artwork. Fast fallback if none is provided: crop the mark from
  the approved mockup as a placeholder PNG. Confirm at implementation.

## Tests (`LenguaTests/Views/Pages/SignInPageTests.swift`, adapted)

`@MainActor` XCTest, `withDependencies`, local `@Shared(.auth)`,
`pfw-testing` + `pfw-custom-dump` (`expectNoDifference`). The live `GIDSignIn`
singleton call is not unit-tested (matches Playola); we test the branches
around it:

- `signInStarted(.google)` is tracked when the flow begins.
- No key window → `.signInError` presented + `reportMessage` called.
- `handleSignInAPIFailure` with a network error → `.signInNetworkError`.
- `handleSignInAPIFailure` with a generic error → `.signInError`, and
  `signInFailed` tracked + reported with expected tags (`auth_method=google`,
  `error_domain`, `error_code`).

## Out of scope (flagged, not doing)

- Apple sign-in implementation (button disabled; follow-up PR).
- Keychain migration for the JWT.
- Real analytics provider wiring (`track` stays a no-op).
- `displayName` / `role` fields on the Lengua `User` model.

## Implementation order (for the plan)

1. SPM + Info.plist + assets (project builds with the SDK linked).
2. Support types: `AnalyticsEvent`, `AnalyticsClient.track`,
   `ErrorReportingClient` (+ classifier/report/error), `UIApplication+keyWindow`,
   `LenguaAlert` factories.
3. API: `signInViaGoogle` client method + live impl + response mapping.
4. `SignInPageModel` (TDD: write `SignInPageTests` first for the testable
   branches, then implement).
5. `SignInPage` view + `LenguaApp` URL/restore wiring.
6. Build, `make test`, `make lint`, `make format-check`.
