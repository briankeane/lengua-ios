import Foundation

@testable import Lengua

extension SRSTrack {
  static func stub(familiarity: Int = 0) -> SRSTrack {
    SRSTrack(
      familiarity: familiarity, nextDueAt: nil, lastSeenAt: nil,
      timesSeen: 0, timesCorrect: 0, timesIncorrect: 0, lastOutcome: nil)
  }
}

extension VocabItem {
  /// Test convenience: build a `VocabItem` from just its identifying fields,
  /// defaulting the server-owned stats and timestamps. Keeps fixtures that only
  /// care about the text (e.g. save-flow tests) concise.
  init(
    id: String, targetLanguageCode: String, sourceText: String, targetText: String,
    receptiveFamiliarity: Int = 0, productiveFamiliarity: Int = 0,
    createdAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    self.init(
      id: id, targetLanguageCode: targetLanguageCode, sourceText: sourceText,
      targetText: targetText,
      receptive: .stub(familiarity: receptiveFamiliarity),
      productive: .stub(familiarity: productiveFamiliarity),
      createdAt: createdAt, updatedAt: createdAt)
  }
}
