import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Lengua

@MainActor
struct TranslatePageModelTests {
  @Test func initialLabelsAreEnglishToSpanish() {
    let model = TranslatePageModel()
    expectNoDifference(model.inputLabel, "English")
    expectNoDifference(model.outputLabel, "Spanish")
    expectNoDifference(model.inputPlaceholder, "Type or speak English")
  }

  @Test func typingTranslatesAfterDebounce() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, direction in
        expectNoDifference(direction, .englishToSpanish)
        return text == "Hello" ? "Hola" : ""
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(499))
    expectNoDifference(model.outputText, "")  // debounce not elapsed
    await clock.advance(by: .milliseconds(1))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "Hola")
    #expect(model.isTranslating == false)
  }

  @Test func rapidTypingDebouncesToOneTranslation() async {
    let clock = TestClock()
    let calls = LockIsolated([String]())
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in
        calls.withValue { $0.append(text) }
        return "translated:\(text)"
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "H"
    model.inputText = "He"
    model.inputText = "Hel"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(calls.value, ["Hel"])
    expectNoDifference(model.outputText, "translated:Hel")
  }

  @Test func clearingInputClearsOutputWithoutTranslating() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "translated:\(text)" }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "translated:Hello")

    model.inputText = "   "
    expectNoDifference(model.outputText, "")  // blank clears immediately, no task
    #expect(model.isTranslating == false)
  }

  @Test func swapFlipsDirectionSwapsTextAndRetranslates() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, direction in
        switch direction {
        case .englishToSpanish: "es:\(text)"
        case .spanishToEnglish: "en:\(text)"
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "es:Hello")

    model.swapButtonTapped()
    expectNoDifference(model.direction, .spanishToEnglish)
    expectNoDifference(model.inputText, "es:Hello")  // texts swapped immediately
    expectNoDifference(model.inputLabel, "Spanish")
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "en:es:Hello")
  }

  @Test func swapDuringInFlightTranslationDiscardsStaleResult() async {
    let clock = TestClock()
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (resume, resumeContinuation) = AsyncStream<String>.makeStream()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in
        startedContinuation.yield()
        var iterator = resume.makeAsyncIterator()
        return await iterator.next() ?? ""
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    let staleTask = model.translationTask
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // the stale translate call is now in flight

    model.swapButtonTapped()
    expectNoDifference(model.direction, .spanishToEnglish)
    expectNoDifference(model.outputText, "Hello")  // swapped text shown immediately

    resumeContinuation.yield("StaleHola")
    resumeContinuation.finish()
    await staleTask?.value  // the stale task resolves, but must not clobber state

    expectNoDifference(model.outputText, "Hello")
    #expect(model.presentedAlert == nil)
    #expect(model.isTranslating == false)
  }

  @Test func translationErrorSurfacesAlert() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in throw TranslatorError.notReady }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.presentedAlert, .translationFailed)
    expectNoDifference(model.outputText, "")
    #expect(model.isTranslating == false)
  }
}
