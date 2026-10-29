import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Lengua

extension TranslatePageModelTests {
  @Test func copyPutsOutputOnPasteboard() async {
    let clock = TestClock()
    let copied = LockIsolated<String?>(nil)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "Hola" }
      $0.pasteboard.copy = { copied.setValue($0) }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    model.copyButtonTapped()
    expectNoDifference(copied.value, "Hola")
    expectNoDifference(model.isOutputCopied, true)
  }

  @Test func copyDoesNothingWhenOutputEmpty() {
    let copied = LockIsolated(false)
    let model = withDependencies {
      $0.pasteboard.copy = { _ in copied.setValue(true) }
    } operation: {
      TranslatePageModel()
    }

    expectNoDifference(model.isCopyEnabled, false)
    model.copyButtonTapped()
    expectNoDifference(copied.value, false)
    expectNoDifference(model.isOutputCopied, false)
  }

  @Test func copyIsDisabledWhileTranslating() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "translated:\(text)" }
      $0.pasteboard.copy = { _ in }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.isCopyEnabled, true)

    model.inputText = "Hello there"
    expectNoDifference(model.isCopyEnabled, false)
  }

  @Test func editingInputResetsCopiedState() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "translated:\(text)" }
      $0.pasteboard.copy = { _ in }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    model.copyButtonTapped()
    expectNoDifference(model.isOutputCopied, true)

    model.inputText = "Hello there"
    expectNoDifference(model.isOutputCopied, false)
  }

  @Test func copyAccessibilityReflectsCopyState() {
    let model = withDependencies {
      $0.pasteboard.copy = { _ in }
    } operation: {
      TranslatePageModel()
    }

    expectNoDifference(model.copyButtonAccessibilityLabel, "Copy translation")
    expectNoDifference(model.copyButtonAccessibilityValue, "")

    model.outputText = "Hola"
    model.copyButtonTapped()

    expectNoDifference(model.copyButtonAccessibilityValue, "Copied")
  }
}
