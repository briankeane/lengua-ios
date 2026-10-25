import CustomDump
import Foundation
import Testing

@testable import Lengua

@MainActor
struct TranslationDirectionTests {
  @Test func englishToSpanishMapsLanguagesAndLabels() {
    let direction = TranslationDirection.englishToSpanish
    expectNoDifference(Locale.Language(identifier: "en"), direction.source)
    expectNoDifference(Locale.Language(identifier: "es-419"), direction.target)
    #expect(direction.inputLabel == "English")
    #expect(direction.outputLabel == "Spanish")
  }

  @Test func spanishToEnglishMapsLanguagesAndLabels() {
    let direction = TranslationDirection.spanishToEnglish
    expectNoDifference(Locale.Language(identifier: "es-419"), direction.source)
    expectNoDifference(Locale.Language(identifier: "en"), direction.target)
    #expect(direction.inputLabel == "Spanish")
    #expect(direction.outputLabel == "English")
  }

  @Test func spanishTranslationLanguageIsLatinAmerican() {
    expectNoDifference("es", TranslationDirection.englishToSpanish.target.languageCode)
    expectNoDifference("419", TranslationDirection.englishToSpanish.target.region)
    expectNoDifference("419", TranslationDirection.spanishToEnglish.source.region)
  }

  @Test func targetLanguageCodeStaysBareISO639() {
    expectNoDifference("es", TranslationDirection.englishToSpanish.targetLanguageCode)
    expectNoDifference("en", TranslationDirection.spanishToEnglish.targetLanguageCode)
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
