import Foundation

/// The two translation directions the app supports. Source of truth for the
/// language pair, the on-screen labels, and the speech locale/voice for each
/// direction. `TranslatorClient` takes a direction; the provider protocol keeps
/// its lower-level `from:/to:` seam.
enum TranslationDirection: String, Sendable, Equatable, CaseIterable, Codable {
  case englishToSpanish
  case spanishToEnglish

  /// Language being translated FROM (the input text's language).
  var source: Locale.Language {
    switch self {
    case .englishToSpanish: Locale.Language(identifier: "en")
    case .spanishToEnglish: Locale.Language(identifier: "es")
    }
  }

  /// Language being translated TO (the output text's language).
  var target: Locale.Language {
    switch self {
    case .englishToSpanish: Locale.Language(identifier: "es")
    case .spanishToEnglish: Locale.Language(identifier: "en")
    }
  }

  /// ISO 639-1 code for the target language, for API payloads (e.g. `"es"`).
  var targetLanguageCode: String {
    switch self {
    case .englishToSpanish: "es"
    case .spanishToEnglish: "en"
    }
  }

  /// Label for the input card (the source language).
  var inputLabel: String {
    switch self {
    case .englishToSpanish: "English"
    case .spanishToEnglish: "Spanish"
    }
  }

  /// Label for the output card (the target language).
  var outputLabel: String {
    switch self {
    case .englishToSpanish: "Spanish"
    case .spanishToEnglish: "English"
    }
  }

  /// Locale for speech recognition — recognizes the INPUT (source) language.
  /// Spanish uses Latin American (`es-MX`), not Castilian (`es-ES`).
  var speechRecognitionLocaleIdentifier: String {
    switch self {
    case .englishToSpanish: "en-US"
    case .spanishToEnglish: "es-MX"
    }
  }

  /// Language for speech synthesis — speaks the OUTPUT (target) language.
  /// Spanish uses a Latin American voice (`es-MX`), not Castilian (`es-ES`).
  var speechSynthesisLanguageIdentifier: String {
    switch self {
    case .englishToSpanish: "es-MX"
    case .spanishToEnglish: "en-US"
    }
  }

  mutating func toggle() {
    self = self == .englishToSpanish ? .spanishToEnglish : .englishToSpanish
  }
}
