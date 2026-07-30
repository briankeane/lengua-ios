import SwiftUI

@MainActor
struct LenguaAlert: Identifiable, Equatable, Hashable {
  nonisolated let id = UUID()
  nonisolated let title: String
  nonisolated let message: String?

  init(title: String, message: String? = nil) {
    self.title = title
    self.message = message
  }

  nonisolated static func == (lhs: LenguaAlert, rhs: LenguaAlert) -> Bool {
    lhs.title == rhs.title && lhs.message == rhs.message
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(title)
    hasher.combine(message)
  }
}

extension View {
  func lenguaAlert(_ alert: Binding<LenguaAlert?>) -> some View {
    self.alert(
      alert.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { alert.wrappedValue != nil },
        set: { if !$0 { alert.wrappedValue = nil } }
      ),
      presenting: alert.wrappedValue,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { presented in if let msg = presented.message { Text(msg) } }
    )
  }
}
