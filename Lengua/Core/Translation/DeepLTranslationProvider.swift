import Foundation

/// DeepL (cloud) is the intended second translation provider. It is **not**
/// implemented yet — this stub exists only to prove the provider seam.
///
/// To implement it later:
///   1. Fill in `translate` with the DeepL HTTP API, mirroring the networking
///      in `APIClient+Live.swift` (Alamofire `Session`, `Config.shared.baseUrl`).
///   2. Add the DeepL API key to `Config` / the `Secrets*.xcconfig` files.
///   3. Return `.deepL` from `TranslationProviderSelector.current` when it should
///      be active (e.g. gated on `Config` or a feature flag).
/// Call sites do not change — they still use `@Dependency(\.translator)`.
struct DeepLTranslationProvider: TranslationProvider {
  func translate(
    _ text: String, from source: Locale.Language, to target: Locale.Language
  ) async throws -> String {
    throw TranslatorError.notImplemented
  }

  func availability(
    from source: Locale.Language, to target: Locale.Language
  ) async -> TranslatorAvailability {
    .unknown
  }
}
