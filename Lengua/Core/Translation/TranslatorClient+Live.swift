import Dependencies
import Foundation

extension TranslatorClient: DependencyKey {
  static var liveValue: TranslatorClient {
    TranslatorClient(
      translate: { text, direction in
        // Provider-agnostic contract: blank input resolves to "" without
        // invoking any provider.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let provider = TranslationProviderSelector.provider(
          for: TranslationProviderSelector.current)
        return try await provider.translate(text, from: direction.source, to: direction.target)
      },
      availability: { direction in
        let provider = TranslationProviderSelector.provider(
          for: TranslationProviderSelector.current)
        return await provider.availability(from: direction.source, to: direction.target)
      },
      prepareTranslation: { direction in
        let provider = TranslationProviderSelector.provider(
          for: TranslationProviderSelector.current)
        try await provider.prepareTranslation(from: direction.source, to: direction.target)
      }
    )
  }
}
