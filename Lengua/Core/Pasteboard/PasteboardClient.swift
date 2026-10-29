import Dependencies
import DependenciesMacros
import UIKit

/// Writes text to the system pasteboard. The page model uses this for the copy
/// button; `UIPasteboard` is an implementation detail in `liveValue`.
@DependencyClient
struct PasteboardClient: Sendable {
  var copy: @Sendable (_ text: String) -> Void
}

extension DependencyValues {
  var pasteboard: PasteboardClient {
    get { self[PasteboardClient.self] }
    set { self[PasteboardClient.self] = newValue }
  }
}

extension PasteboardClient: DependencyKey {
  static var liveValue: PasteboardClient {
    PasteboardClient(copy: { text in UIPasteboard.general.string = text })
  }
  static let testValue = PasteboardClient()
}
