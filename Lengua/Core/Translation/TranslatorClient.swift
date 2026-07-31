import Dependencies
import DependenciesMacros
import Foundation

/// Shared service that translates English into Spanish.
///
/// Call sites only ever touch this client (`@Dependency(\.translator)`); the
/// underlying provider (Apple on-device now, DeepL later) is an implementation
/// detail selected in `liveValue`. Swapping providers requires no call-site
/// changes. See `TranslationProvider` for the provider seam.
@DependencyClient
struct TranslatorClient: Sendable {
  /// Translates `text` in the given `direction`. Empty / whitespace-only input
  /// resolves to an empty string without invoking a provider.
  var translate:
    @Sendable (_ text: String, _ direction: TranslationDirection) async throws -> String

  /// Whether the active provider can translate `direction` right now, needs a
  /// model download, or does not support the pair.
  var availability: @Sendable (_ direction: TranslationDirection) async -> TranslatorAvailability =
    { _ in .unknown }
}

/// Domain error for translation. Named `TranslatorError` (not `TranslationError`)
/// to avoid confusion with Apple's `Translation.TranslationError`.
enum TranslatorError: Error, Equatable {
  /// No translation session is available yet (Apple provider host not mounted).
  case notReady
  /// The language model must be downloaded before translating.
  case downloadRequired
  /// The English → Spanish pair is not supported on this device.
  case unsupportedLanguagePair
  /// The selected provider has not been implemented (e.g. the DeepL stub).
  case notImplemented
  /// The provider failed to translate; associated value is a diagnostic string.
  case translationFailed(String)
}

/// Readiness of the active provider for the English → Spanish pair.
enum TranslatorAvailability: Equatable, Sendable {
  /// Ready to translate immediately.
  case installed
  /// Supported, but the on-device model must be downloaded first.
  case downloadRequired
  /// Not supported on this device.
  case unsupported
  /// Could not be determined (e.g. running in the Simulator).
  case unknown
}

extension DependencyValues {
  var translator: TranslatorClient {
    get { self[TranslatorClient.self] }
    set { self[TranslatorClient.self] = newValue }
  }
}

extension TranslatorClient: TestDependencyKey {
  static let testValue = TranslatorClient()
}
