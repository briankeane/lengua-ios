import Foundation
import Testing

@testable import Lengua

@MainActor
struct TranslationDirectionTests {
  @Test func englishToSpanishMapsLanguagesAndLabels() {
    let direction = TranslationDirection.englishToSpanish
    #expect(direction.source == Locale.Language(identifier: "en"))
    #expect(direction.target == Locale.Language(identifier: "es-419"))
    #expect(direction.inputLabel == "English")
    #expect(direction.outputLabel == "Spanish")
  }

  @Test func spanishToEnglishMapsLanguagesAndLabels() {
    let direction = TranslationDirection.spanishToEnglish
    #expect(direction.source == Locale.Language(identifier: "es-419"))
    #expect(direction.target == Locale.Language(identifier: "en"))
    #expect(direction.inputLabel == "Spanish")
    #expect(direction.outputLabel == "English")
  }

  @Test func spanishTranslationLanguageIsLatinAmerican() {
    #expect(TranslationDirection.englishToSpanish.target.languageCode == "es")
    #expect(TranslationDirection.englishToSpanish.target.region == "419")
    #expect(TranslationDirection.spanishToEnglish.source.region == "419")
  }

  @Test func targetLanguageCodeStaysBareISO639() {
    #expect(TranslationDirection.englishToSpanish.targetLanguageCode == "es")
    #expect(TranslationDirection.spanishToEnglish.targetLanguageCode == "en")
  }

  @Test func speechIdentifiersFollowSourceAndTarget() {
    #expect(TranslationDirection.englishToSpanish.speechRecognitionLocaleIdentifier == "en-US")
    #expect(TranslationDirection.englishToSpanish.speechSynthesisLanguageIdentifier == "es-MX")
    #expect(TranslationDirection.spanishToEnglish.speechRecognitionLocaleIdentifier == "es-MX")
    #expect(TranslationDirection.spanishToEnglish.speechSynthesisLanguageIdentifier == "en-US")
  }

  @Test func toggleFlipsDirection() {
    var direction = TranslationDirection.englishToSpanish
    direction.toggle()
    #expect(direction == .spanishToEnglish)
    direction.toggle()
    #expect(direction == .englishToSpanish)
  }
}
