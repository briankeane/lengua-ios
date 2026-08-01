import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Lengua

@Suite(.serialized)
@MainActor
struct TranslatePageModelTests {
  @Test func initialLabelsAreEnglishToSpanish() {
    let model = TranslatePageModel()
    expectNoDifference(model.inputLabel, "English")
    expectNoDifference(model.outputLabel, "Spanish")
    expectNoDifference(model.inputPlaceholder, "Type or speak English")
  }

  @Test func doneButtonDismissesKeyboardTitle() {
    let model = TranslatePageModel()
    expectNoDifference(model.doneButtonTitle, "Done")
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

  @Test func pageDisappearingCancelsInFlightTranslationSoNoStaleAlert() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in throw TranslatorError.notReady }
      $0.speechSynthesizer.stop = {}
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"  // schedules a translation; task is debouncing
    model.pageDisappeared()  // leaving the page cancels it mid-debounce
    await model.translationTask?.value

    // The cancelled task must not run the failing translate or set an alert.
    #expect(model.presentedAlert == nil)
    expectNoDifference(model.outputText, "")
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

  @Test func speakerSpeaksOutputInTargetLanguage() async {
    let clock = TestClock()
    let spoken = LockIsolated<(String, String)?>(nil)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "Hola" }
      $0.speechSynthesizer.speak = { text, language in spoken.setValue((text, language)) }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.speakerButtonTapped()
    expectNoDifference(spoken.value?.0, "Hola")
    expectNoDifference(spoken.value?.1, "es-MX")  // Latin American Spanish output
  }

  @Test func speakerDoesNothingWhenOutputEmpty() async {
    let called = LockIsolated(false)
    let model = withDependencies {
      $0.speechSynthesizer.speak = { _, _ in called.setValue(true) }
    } operation: {
      TranslatePageModel()
    }

    await model.speakerButtonTapped()
    #expect(called.value == false)
  }

  @Test func outputDisplayFallsBackToPlaceholderUntilTranslated() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "Hola" }
    } operation: {
      TranslatePageModel()
    }

    #expect(model.outputIsPlaceholder == true)
    expectNoDifference(model.outputDisplayText, model.outputPlaceholder)

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    #expect(model.outputIsPlaceholder == false)
    expectNoDifference(model.outputDisplayText, model.outputText)
  }
}

extension TranslatePageModelTests {
  @Test func saveIsDisabledUntilTranslationPresent() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "Hola" }
    } operation: {
      TranslatePageModel()
    }

    #expect(model.isSaveEnabled == false)

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    #expect(model.isSaveEnabled == true)
  }

  @Test func saveSendsTrimmedRequestAndMarksSaved() async {
    let clock = TestClock()
    let captured = LockIsolated<SaveVocabItemRequest?>(nil)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "el perro" }
      $0.api.saveVocabItem = { request in
        captured.setValue(request)
        return VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "the dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.saveButtonTapped()

    expectNoDifference(
      captured.value,
      SaveVocabItemRequest(
        targetLanguageCode: "es", sourceText: "the dog", targetText: "el perro"))
    expectNoDifference(model.saveState, .saved)
    expectNoDifference(model.saveButtonTitle, "Saved")
    #expect(model.isSaveEnabled == false)
  }

  @Test func saveUsesTargetLanguageCodeForActiveDirection() async {
    let clock = TestClock()
    let captured = LockIsolated<SaveVocabItemRequest?>(nil)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "the dog" }
      $0.api.saveVocabItem = { request in
        captured.setValue(request)
        return VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.direction = .spanishToEnglish
    model.inputText = "el perro"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.saveButtonTapped()

    expectNoDifference(captured.value?.targetLanguageCode, "en")
    expectNoDifference(captured.value?.sourceText, "el perro")
    expectNoDifference(captured.value?.targetText, "the dog")
  }

  @Test func saveFailureSurfacesAlertAndResetsState() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "el perro" }
      $0.api.saveVocabItem = { _ in throw APIError.validationError("boom") }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "the dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.saveButtonTapped()

    expectNoDifference(model.saveState, .idle)
    expectNoDifference(model.presentedAlert, .saveFailed)
    #expect(model.isSaveEnabled == true)
  }

  @Test func editingAfterSaveClearsSavedState() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "t:\(text)" }
      $0.api.saveVocabItem = { request in
        VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    await model.saveButtonTapped()
    expectNoDifference(model.saveState, .saved)

    model.inputText = "dogs"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    expectNoDifference(model.saveState, .idle)  // a fresh translation is unsaved
    #expect(model.isSaveEnabled == true)
  }

  @Test func saveDoesNothingWithoutTranslation() async {
    let called = LockIsolated(false)
    let model = withDependencies {
      $0.api.saveVocabItem = { _ in
        called.setValue(true)
        return VocabItem(id: "", targetLanguageCode: "", sourceText: "", targetText: "")
      }
    } operation: {
      TranslatePageModel()
    }

    await model.saveButtonTapped()

    #expect(called.value == false)
    expectNoDifference(model.saveState, .idle)
  }
}

extension TranslatePageModelTests {
  @Test func editingInputClearsSavedStateImmediately() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "el perro" }
      $0.api.saveVocabItem = { request in
        VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "the dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    await model.saveButtonTapped()
    expectNoDifference(model.saveState, .saved)

    model.inputText = "the dogs"  // editing the source is unsaved, immediately
    expectNoDifference(model.saveState, .idle)
  }

  @Test func unauthorizedSaveSurfacesSignInAlert() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "el perro" }
      $0.api.saveVocabItem = { _ in throw APIError.unauthorized }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "the dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.saveButtonTapped()

    expectNoDifference(model.presentedAlert, .saveRequiresSignIn)
    expectNoDifference(model.saveState, .idle)
  }

  @Test func saveBlockedWhileOutputIsStaleAfterEdit() async {
    let clock = TestClock()
    let saveCalled = LockIsolated(false)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in text == "the dog" ? "el perro" : "el gato" }
      $0.api.saveVocabItem = { request in
        saveCalled.setValue(true)
        return VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "the dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "el perro")

    // Editing the source leaves the old target visible until retranslation lands.
    model.inputText = "the cat"
    #expect(model.isTranslating == true)
    #expect(model.isSaveEnabled == false)

    await model.saveButtonTapped()  // must not persist the mismatched pair
    #expect(saveCalled.value == false)
    expectNoDifference(model.saveState, .idle)

    // Once retranslation completes, the correct pair can be saved.
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(model.outputText, "el gato")
    #expect(model.isSaveEnabled == true)
  }

  @Test func editingMidSaveDiscardsStaleSavedResult() async {
    let clock = TestClock()
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (resume, resumeContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "t:\(text)" }
      $0.api.saveVocabItem = { request in
        startedContinuation.yield()
        var iterator = resume.makeAsyncIterator()
        _ = await iterator.next()
        return VocabItem(
          id: "v1", targetLanguageCode: request.targetLanguageCode,
          sourceText: request.sourceText, targetText: request.targetText)
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "dog"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    let saveTask = Task { await model.saveButtonTapped() }
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // save request is in flight
    expectNoDifference(model.saveState, .saving)

    model.inputText = "dogs"  // edit mid-save: changes the term being saved
    expectNoDifference(model.saveState, .idle)

    resumeContinuation.yield()
    resumeContinuation.finish()
    await saveTask.value

    expectNoDifference(model.saveState, .idle)  // stale success must not mark .saved
  }
}

extension TranslatePageModelTests {
  @Test func speakerErrorSurfacesAlert() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in "Hola" }
      $0.speechSynthesizer.speak = { _, _ in throw TranslatorError.notReady }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    await model.speakerButtonTapped()
    expectNoDifference(model.presentedAlert, .speechSynthesisFailed)
  }
}

extension TranslatePageModelTests {
  @Test func micDictationFlowsIntoInputText() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "translated:\(text)" }
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = {}
      $0.speechSynthesizer.stop = {}
      $0.speechRecognizer.start = { locale in
        expectNoDifference(locale, "en-US")
        return AsyncThrowingStream { continuation in
          continuation.yield(SpeechRecognitionResult(transcript: "Hello", isFinal: false))
          continuation.yield(SpeechRecognitionResult(transcript: "Hello world", isFinal: true))
          continuation.finish()
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    await model.recognitionTask?.value
    expectNoDifference(model.inputText, "Hello world")
    #expect(model.isRecording == false)
  }

  @Test func micPermissionDeniedSurfacesAlert() async {
    let model = withDependencies {
      $0.speechRecognizer.requestAuthorization = { .denied }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    await model.recognitionTask?.value
    expectNoDifference(model.presentedAlert, .speechRecognitionPermissionDenied)
    #expect(model.isRecording == false)
  }

  @Test func micFailureSurfacesAlert() async {
    let model = withDependencies {
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = {}
      $0.speechSynthesizer.stop = {}
      $0.speechRecognizer.start = { _ in
        AsyncThrowingStream { $0.finish(throwing: TranslatorError.notReady) }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    await model.recognitionTask?.value
    expectNoDifference(model.presentedAlert, .speechRecognitionFailed)
    #expect(model.isRecording == false)
  }

  @Test func secondMicTapStopsDictation() async {
    let stopped = LockIsolated(false)
    let (streaming, streamingContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = { stopped.setValue(true) }
      $0.speechSynthesizer.stop = {}
      $0.speechRecognizer.start = { _ in
        // A stream that stays open until the recognition task is cancelled,
        // standing in for a live dictation session. Signal once it is live so the
        // test cancels an actually-streaming session, not one still authorizing.
        AsyncThrowingStream { continuation in
          streamingContinuation.yield()
          streamingContinuation.finish()
          continuation.onTermination = { _ in continuation.finish() }
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    var iterator = streaming.makeAsyncIterator()
    await iterator.next()  // dictation is now past authorization and streaming
    #expect(model.isRecording == true)

    model.micButtonTapped()  // second tap cancels the active recognition stream
    await model.recognitionTask?.value
    #expect(model.isRecording == false)
    #expect(stopped.value == true)
  }

  @Test func cancellingDuringAuthorizationDoesNotStartRecording() async {
    let started = LockIsolated(false)
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.speechRecognizer.requestAuthorization = {
        var iterator = gate.makeAsyncIterator()
        await iterator.next()  // suspend until the test releases the gate
        return .authorized
      }
      $0.speechRecognizer.start = { _ in
        started.setValue(true)
        return AsyncThrowingStream { $0.finish() }
      }
      $0.speechRecognizer.stop = {}
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()  // task suspends awaiting authorization
    #expect(model.isRecording == true)
    model.micButtonTapped()  // second tap cancels the task mid-authorization
    gateContinuation.yield()  // authorization now resolves to .authorized
    gateContinuation.finish()
    await model.recognitionTask?.value

    #expect(started.value == false)  // cancelled before the recognizer started
    #expect(model.isRecording == false)
  }

  @Test func speakerStopsActiveDictationBeforeSpeaking() async {
    let recognizerStopped = LockIsolated(false)
    let spoke = LockIsolated(false)
    let (streaming, streamingContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = { recognizerStopped.setValue(true) }
      $0.speechSynthesizer.stop = {}
      $0.speechSynthesizer.speak = { _, _ in spoke.setValue(true) }
      $0.speechRecognizer.start = { _ in
        AsyncThrowingStream { continuation in
          streamingContinuation.yield()
          streamingContinuation.finish()
          continuation.onTermination = { _ in continuation.finish() }
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    var iterator = streaming.makeAsyncIterator()
    await iterator.next()  // dictation is live
    #expect(model.isRecording == true)

    model.outputText = "Hola"  // give the speaker something to say
    await model.speakerButtonTapped()

    #expect(recognizerStopped.value == true)  // dictation stopped before TTS spoke
    #expect(spoke.value == true)
    #expect(model.isRecording == false)
  }
}

extension TranslatePageModelTests {
  private typealias Continuation =
    AsyncThrowingStream<SpeechRecognitionResult, Error>.Continuation

  @Test func lateTranscriptAfterPageDisappearedIsIgnored() async {
    let clock = TestClock()
    let translateCalls = LockIsolated(0)
    let box = LockIsolated<Continuation?>(nil)
    let (streaming, streamingContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in
        translateCalls.withValue { $0 += 1 }
        return "t:\(text)"
      }
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = {}
      $0.speechSynthesizer.stop = {}
      $0.speechRecognizer.start = { _ in
        AsyncThrowingStream { continuation in
          box.setValue(continuation)
          streamingContinuation.yield()
          streamingContinuation.finish()
          continuation.onTermination = { _ in continuation.finish() }
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    var iterator = streaming.makeAsyncIterator()
    await iterator.next()  // dictation is live
    model.pageDisappeared()  // cancels dictation
    await model.recognitionTask?.value

    // A transcript that arrives after cancellation must not write input or restart
    // translation.
    box.value?.yield(SpeechRecognitionResult(transcript: "late", isFinal: true))
    box.value?.finish()

    expectNoDifference(model.inputText, "")
    expectNoDifference(translateCalls.value, 0)
  }

  @Test func lateTranscriptAfterSwapDoesNotOverwriteInput() async {
    let clock = TestClock()
    let box = LockIsolated<Continuation?>(nil)
    let (streaming, streamingContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "t:\(text)" }
      $0.speechRecognizer.requestAuthorization = { .authorized }
      $0.speechRecognizer.stop = {}
      $0.speechSynthesizer.stop = {}
      $0.speechRecognizer.start = { _ in
        AsyncThrowingStream { continuation in
          box.setValue(continuation)
          streamingContinuation.yield()
          streamingContinuation.finish()
          continuation.onTermination = { _ in continuation.finish() }
        }
      }
    } operation: {
      TranslatePageModel()
    }

    model.micButtonTapped()
    var iterator = streaming.makeAsyncIterator()
    await iterator.next()  // dictation is live
    model.swapButtonTapped()  // cancels dictation and flips direction
    await model.recognitionTask?.value

    box.value?.yield(SpeechRecognitionResult(transcript: "late", isFinal: true))
    box.value?.finish()

    expectNoDifference(model.inputText, "")
    expectNoDifference(model.direction, .spanishToEnglish)
  }
}
