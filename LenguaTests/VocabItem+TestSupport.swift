import Foundation

@testable import Lengua

extension VocabItem {
  /// Test convenience: build a `VocabItem` from just its identifying fields,
  /// defaulting the server-owned stats and timestamps. Keeps fixtures that only
  /// care about the text (e.g. save-flow tests) concise.
  init(id: String, targetLanguageCode: String, sourceText: String, targetText: String) {
    self.init(
      id: id,
      targetLanguageCode: targetLanguageCode,
      sourceText: sourceText,
      targetText: targetText,
      familiarity: 0,
      lastSeenAt: nil,
      timesSeen: 0,
      timesCorrect: 0,
      timesIncorrect: 0,
      lastOutcome: nil,
      nextDueAt: nil,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0))
  }
}
