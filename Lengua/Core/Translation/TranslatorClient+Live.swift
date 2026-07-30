import Dependencies
import Foundation

extension TranslatorClient: DependencyKey {
  static var liveValue: TranslatorClient {
    // Scope is fixed English → Spanish. Use explicit language tags rather than
    // inferring from the device locale.
    let source = Locale.Language(identifier: "en")
    let target = Locale.Language(identifier: "es")

    return TranslatorClient(
      translate: { text in
        // Provider-agnostic contract: blank input resolves to "" without
        // invoking any provider (so the behaviour holds when DeepL is swapped
        // in, not just for the Apple provider).
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let provider = TranslationProviderSelector.provider(
          for: TranslationProviderSelector.current)
        return try await provider.translate(text, from: source, to: target)
      },
      availability: {
        let provider = TranslationProviderSelector.provider(
          for: TranslationProviderSelector.current)
        return await provider.availability(from: source, to: target)
      }
    )
  }
}
