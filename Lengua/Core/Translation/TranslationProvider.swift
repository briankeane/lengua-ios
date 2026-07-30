import Foundation

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

/// The set of translation backends the app knows about.
enum TranslationProviderKind: Sendable, Equatable, CaseIterable {
  /// Apple's on-device Translation framework (iOS 18+). The active default.
  case apple
  /// DeepL cloud provider — intended second provider, not yet implemented.
  case deepL
}

/// Chooses which provider backs `TranslatorClient`. This is the seam: to enable
/// DeepL later, implement `DeepLTranslationProvider` and change `current` (e.g.
/// gate it on `Config` / a feature flag). Call sites never change.
enum TranslationProviderSelector {
  /// Apple on-device is the active default provider.
  static var current: TranslationProviderKind { .apple }

  static func provider(for kind: TranslationProviderKind) -> any TranslationProvider {
    switch kind {
    case .apple: AppleTranslationProvider()
    case .deepL: DeepLTranslationProvider()
    }
  }
}
