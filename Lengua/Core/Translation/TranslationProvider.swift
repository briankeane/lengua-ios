import Foundation
import Sharing

/// A concrete translation backend. Internal to the Translator service — not a
/// dependency boundary. `TranslatorClient` is the only thing call sites inject;
/// which provider backs it is decided by `TranslationProviderSelector`.
///
/// Adding a new provider (e.g. DeepL) is a localized change: conform a new type
/// to this protocol and return it from the selector. No call site changes.
protocol TranslationProvider: Sendable {
  func translate(
    _ text: String, from source: Locale.Language, to target: Locale.Language
  ) async throws -> String

  func availability(
    from source: Locale.Language, to target: Locale.Language
  ) async -> TranslatorAvailability
}

/// The set of translation backends the app knows about. `String`-backed +
/// `Codable` so the user's choice can be persisted via `@Shared(.appStorage)`.
enum TranslationProviderKind: String, Sendable, Equatable, CaseIterable, Codable {
  /// Apple's on-device Translation framework (iOS 18+). The active default.
  case apple
  /// DeepL cloud provider — intended second provider, not yet implemented.
  case deepL

  /// Whether this provider can be selected yet. DeepL is not implemented, so it
  /// is shown but disabled in the UI.
  var isEnabled: Bool {
    switch self {
    case .apple: true
    case .deepL: false
    }
  }

  /// Human-readable name for settings UI.
  var displayName: String {
    switch self {
    case .apple: "Apple"
    case .deepL: "DeepL"
    }
  }
}

/// Chooses which provider backs `TranslatorClient`. This is the seam: to enable
/// DeepL later, implement `DeepLTranslationProvider` and change `current` (e.g.
/// gate it on `Config` / a feature flag). Call sites never change.
enum TranslationProviderSelector {
  /// The user's chosen provider, read fresh from persisted preference each call.
  /// `TranslatorClient+Live`'s closures run per-call, so this always reflects the
  /// current setting without any wiring at call sites.
  static var current: TranslationProviderKind {
    @Shared(.translationProviderKind) var providerKind
    return providerKind
  }

  static func provider(for kind: TranslationProviderKind) -> any TranslationProvider {
    switch kind {
    case .apple: AppleTranslationProvider()
    case .deepL: DeepLTranslationProvider()
    }
  }
}
