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

extension LenguaAlert {
  static var signInError: LenguaAlert {
    LenguaAlert(
      title: "Sign-In Failed",
      message:
        "Something went wrong on our end while signing you in. Please try again. "
        + "If it keeps happening, contact us at lonesomewhistle@gmail.com and we'll "
        + "help get you sorted.")
  }

  static var signInNetworkError: LenguaAlert {
    LenguaAlert(
      title: "Connection Issue",
      message:
        "Your network is blocking the secure connection to Lengua. Try turning "
        + "off wifi and using cellular data, or switch to a different wifi "
        + "network. (More info: https://support.apple.com/en-us/122756)")
  }

  static var translationFailed: LenguaAlert {
    LenguaAlert(
      title: "Translation Failed",
      message: "We couldn't translate that just now. Check your connection and try again.")
  }

  static var saveFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Save",
      message: "We couldn't save that word just now. Check your connection and try again.")
  }

  static var deleteFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Delete",
      message: "We couldn't delete that word just now. Check your connection and try again.")
  }

  static var saveRequiresSignIn: LenguaAlert {
    LenguaAlert(
      title: "Sign In to Save",
      message: "Sign in to save words to your vocabulary.")
  }

  static var speechSynthesisFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Play Audio",
      message: "We couldn't read that aloud just now. Please try again.")
  }

  static var speechRecognitionPermissionDenied: LenguaAlert {
    LenguaAlert(
      title: "Microphone Access Needed",
      message:
        "To speak your translation, allow microphone and speech recognition "
        + "access for Lengua in Settings.")
  }

  static var speechRecognitionFailed: LenguaAlert {
    LenguaAlert(
      title: "Couldn't Hear You",
      message: "Speech recognition stopped unexpectedly. Please try again.")
  }
}
