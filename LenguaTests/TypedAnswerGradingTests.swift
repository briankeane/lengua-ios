import CustomDump
import Testing

@testable import Lengua

@Suite struct TypedAnswerGradingTests {
  @Test func exactMatchIsCorrect() {
    expectNoDifference(gradeTypedAnswer("el perro", expected: "el perro"), .correct)
  }
  @Test func caseAndWhitespaceAndTrimNormalize() {
    expectNoDifference(gradeTypedAnswer("  EL   Perro ", expected: "el perro"), .correct)
  }
  @Test func vowelAccentDifferenceIsAccentNote() {
    expectNoDifference(
      gradeTypedAnswer("el pinguino", expected: "el pingüino"), .correctWithAccentNote)
    expectNoDifference(gradeTypedAnswer("cafe", expected: "café"), .correctWithAccentNote)
  }
  @Test func enyeIsADistinctLetterNotAnAccent() {
    expectNoDifference(gradeTypedAnswer("ano", expected: "año"), .incorrect)
  }
  @Test func droppedArticleIsIncorrect() {
    expectNoDifference(gradeTypedAnswer("perro", expected: "el perro"), .incorrect)
  }
  @Test func wrongWordIsIncorrect() {
    expectNoDifference(gradeTypedAnswer("gato", expected: "perro"), .incorrect)
  }
}
