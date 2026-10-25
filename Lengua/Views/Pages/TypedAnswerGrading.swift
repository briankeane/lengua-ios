import Foundation

enum TypedGrade: Equatable, Sendable {
  case correct
  case correctWithAccentNote
  case incorrect
}

/// Forgiving comparison of a typed productive answer to the expected target text.
/// Fixed-locale lowercasing (avoids the Turkish dotless-i trap), NFC via
/// `precomposedStringWithCanonicalMapping`, and vowel-accent-only leniency.
/// `ñ` is a distinct letter, never treated as an accent variant of `n`.
func gradeTypedAnswer(_ typed: String, expected: String) -> TypedGrade {
  let normalizedTyped = normalize(typed)
  let normalizedExpected = normalize(expected)
  if normalizedTyped == normalizedExpected { return .correct }
  if foldVowelAccents(normalizedTyped) == foldVowelAccents(normalizedExpected) {
    return .correctWithAccentNote
  }
  return .incorrect
}

private func normalize(_ text: String) -> String {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  return
    collapsed
    .lowercased(with: Locale(identifier: "en_US_POSIX"))
    .precomposedStringWithCanonicalMapping
}

private func foldVowelAccents(_ text: String) -> String {
  let map: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u"]
  return String(text.map { map[$0] ?? $0 })
}
