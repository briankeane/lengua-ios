import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Lengua

extension TranslatePageModelTests {
  @Test func downloadRequiredErrorShowsAffordanceNotAlert() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in throw TranslatorError.downloadRequired }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    expectNoDifference(model.downloadRequiredDirection, .englishToSpanish)
    #expect(model.showsDownloadPrompt == true)
    #expect(model.presentedAlert == nil)  // no dead-end alert
    expectNoDifference(model.outputText, "")
    #expect(model.isTranslating == false)
  }

  @Test func pageAppearedAutoProvokesDownloadOnceWhenModelMissing() async {
    let provokeCalls = LockIsolated(0)
    let model = withDependencies {
      $0.translator.availability = { _ in .downloadRequired }
      $0.translator.prepareTranslation = { _ in
        provokeCalls.withValue { $0 += 1 }
        throw TranslatorError.downloadRequired  // user dismisses the system sheet
      }
    } operation: {
      TranslatePageModel()
    }

    await model.pageAppeared()

    expectNoDifference(provokeCalls.value, 1)
    expectNoDifference(model.downloadRequiredDirection, .englishToSpanish)
    #expect(model.showsDownloadPrompt == true)
  }

  @Test func pageAppearedDoesNotAutoReprovokeOnSecondAppear() async {
    let provokeCalls = LockIsolated(0)
    let model = withDependencies {
      $0.translator.availability = { _ in .downloadRequired }
      $0.translator.prepareTranslation = { _ in
        provokeCalls.withValue { $0 += 1 }
        throw TranslatorError.downloadRequired
      }
    } operation: {
      TranslatePageModel()
    }

    await model.pageAppeared()
    await model.pageAppeared()  // still missing, but auto-gate is spent

    expectNoDifference(provokeCalls.value, 1)
    #expect(model.showsDownloadPrompt == true)  // affordance remains for manual retry
  }

  @Test func pageAppearedUnknownAvailabilityDoesNotProvoke() async {
    // The Simulator reports `.unknown`; nothing should auto-loop there.
    let provokeCalls = LockIsolated(0)
    let model = withDependencies {
      $0.translator.availability = { _ in .unknown }
      $0.translator.prepareTranslation = { _ in provokeCalls.withValue { $0 += 1 } }
    } operation: {
      TranslatePageModel()
    }

    await model.pageAppeared()

    expectNoDifference(provokeCalls.value, 0)
    expectNoDifference(model.downloadRequiredDirection, nil)
  }

  @Test func downloadButtonReprovokesEvenAfterAutoPromptSpent() async {
    // Manual taps are user intent — they are NOT gated by the auto-gate, so each
    // tap provokes the sheet again.
    let provokeCalls = LockIsolated(0)
    let model = withDependencies {
      $0.translator.availability = { _ in .downloadRequired }
      $0.translator.prepareTranslation = { _ in
        provokeCalls.withValue { $0 += 1 }
        throw TranslatorError.downloadRequired
      }
    } operation: {
      TranslatePageModel()
    }

    await model.pageAppeared()  // auto-provoke #1
    model.downloadButtonTapped()  // manual #2
    await model.downloadTask?.value
    model.downloadButtonTapped()  // manual #3
    await model.downloadTask?.value

    expectNoDifference(provokeCalls.value, 3)
  }

  @Test func concurrentDownloadTapsDoNotStack() async {
    let provokeCalls = LockIsolated(0)
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (resume, resumeContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.translator.prepareTranslation = { _ in
        provokeCalls.withValue { $0 += 1 }
        startedContinuation.yield()
        var iterator = resume.makeAsyncIterator()
        await iterator.next()  // suspend the first provoke until released
      }
    } operation: {
      TranslatePageModel()
    }

    model.downloadButtonTapped()  // sync: sets isPreparingDownload, starts downloadTask
    #expect(model.isPreparingDownload == true)
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // first provoke is in flight

    model.downloadButtonTapped()  // second tap is dropped by the manual gate
    expectNoDifference(provokeCalls.value, 1)

    resumeContinuation.yield()
    resumeContinuation.finish()
    await model.downloadTask?.value
    #expect(model.isPreparingDownload == false)
  }

  @Test func successfulDownloadResumesTranslationOfCurrentInput() async {
    let clock = TestClock()
    let prepared = LockIsolated(false)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in
        guard prepared.value else { throw TranslatorError.downloadRequired }
        return "es:\(text)"
      }
      $0.translator.prepareTranslation = { _ in prepared.setValue(true) }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    #expect(model.showsDownloadPrompt == true)  // model missing: affordance shown
    expectNoDifference(model.outputText, "")

    model.downloadButtonTapped()  // prepare succeeds -> resume translation
    await model.downloadTask?.value
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value

    expectNoDifference(model.downloadRequiredDirection, nil)
    expectNoDifference(model.outputText, "es:Hello")
  }

  @Test func staleDownloadDismissDoesNotResurrectOldDirectionPrompt() async {
    let clock = TestClock()
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (resume, resumeContinuation) = AsyncStream<Void>.makeStream()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { text, _ in "t:\(text)" }
      $0.translator.prepareTranslation = { _ in
        startedContinuation.yield()
        var iterator = resume.makeAsyncIterator()
        await iterator.next()
        throw TranslatorError.downloadRequired  // dismissed, but for the stale direction
      }
    } operation: {
      TranslatePageModel()
    }

    model.downloadRequiredDirection = .englishToSpanish
    model.downloadButtonTapped()  // starts downloadTask for englishToSpanish
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // provoke in flight for englishToSpanish

    model.swapButtonTapped()  // direction flips; clears the prompt
    expectNoDifference(model.downloadRequiredDirection, nil)

    resumeContinuation.yield()
    resumeContinuation.finish()
    await model.downloadTask?.value

    // The stale dismissal must not resurrect the old direction's prompt.
    expectNoDifference(model.downloadRequiredDirection, nil)
    expectNoDifference(model.direction, .spanishToEnglish)
  }

}

extension TranslatePageModelTests {
  @Test func pageAppearedInstalledClearsStalePrompt() async {
    let model = withDependencies {
      $0.translator.availability = { _ in .installed }
    } operation: {
      TranslatePageModel()
    }

    model.downloadRequiredDirection = .englishToSpanish
    await model.pageAppeared()

    expectNoDifference(model.downloadRequiredDirection, nil)
  }

  @Test func swapClearsDownloadPrompt() async {
    let clock = TestClock()
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in throw TranslatorError.downloadRequired }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    #expect(model.showsDownloadPrompt == true)

    model.swapButtonTapped()
    expectNoDifference(model.downloadRequiredDirection, nil)
    #expect(model.showsDownloadPrompt == false)
  }

  @Test func editingWhileDownloadRequiredDoesNotRetranslate() async {
    // Once the prompt is up, further keystrokes must NOT re-run translate — a
    // translate re-provokes the system sheet, so this is what stops the sheet
    // re-popping on every character. Only the Download button re-provokes.
    let clock = TestClock()
    let translateCalls = LockIsolated(0)
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.translate = { _, _ in
        translateCalls.withValue { $0 += 1 }
        throw TranslatorError.downloadRequired
      }
    } operation: {
      TranslatePageModel()
    }

    model.inputText = "Hello"
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(translateCalls.value, 1)
    #expect(model.showsDownloadPrompt == true)

    model.inputText = "Hello!"  // edit while the prompt is up
    await clock.advance(by: .milliseconds(500))
    await model.translationTask?.value
    expectNoDifference(translateCalls.value, 1)  // gated: no re-translate, no re-pop
    #expect(model.showsDownloadPrompt == true)
  }

  @Test func pageDisappearingCancelsDownloadProvoke() async {
    // A manual download provoke is an unstructured task; leaving the tab must
    // cancel it so it can't mutate prompt/alert state off-page.
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let observedCancellation = LockIsolated(false)
    let model = withDependencies {
      $0.speechSynthesizer.stop = {}
      $0.translator.prepareTranslation = { _ in
        startedContinuation.yield()
        var iterator = release.makeAsyncIterator()
        await iterator.next()  // suspend the provoke mid-flight
        observedCancellation.setValue(Task.isCancelled)
      }
    } operation: {
      TranslatePageModel()
    }

    model.downloadRequiredDirection = .englishToSpanish
    model.downloadButtonTapped()
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // provoke in flight

    model.pageDisappeared()  // must cancel the download task
    releaseContinuation.yield()
    releaseContinuation.finish()
    await model.downloadTask?.value

    #expect(observedCancellation.value == true)  // the provoke saw the cancellation
    // Cancelled: must not clear the prompt or schedule a translation off-page.
    expectNoDifference(model.downloadRequiredDirection, .englishToSpanish)
    #expect(model.isPreparingDownload == false)
  }

  @Test func staleAvailabilityAfterSwapDoesNotProvokeWrongDirection() async {
    // pageAppeared's availability query is a suspension point. If the direction
    // flips while it is in flight, the stale result must not provoke the old
    // direction's sheet or set its prompt.
    let clock = TestClock()
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let provokedDirections = LockIsolated<[TranslationDirection]>([])
    let model = withDependencies {
      $0.continuousClock = clock
      $0.translator.availability = { _ in
        startedContinuation.yield()
        var iterator = release.makeAsyncIterator()
        await iterator.next()  // suspend availability mid-appear
        return .downloadRequired
      }
      $0.translator.prepareTranslation = { direction in
        provokedDirections.withValue { $0.append(direction) }
        throw TranslatorError.downloadRequired
      }
      $0.translator.translate = { text, _ in "t:\(text)" }
    } operation: {
      TranslatePageModel()
    }

    let appear = Task { await model.pageAppeared() }
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()  // availability suspended for englishToSpanish
    model.swapButtonTapped()  // direction flips to spanishToEnglish
    releaseContinuation.yield()
    releaseContinuation.finish()
    await appear.value

    expectNoDifference(provokedDirections.value, [])  // stale result did not provoke
    #expect(model.showsDownloadPrompt == false)
  }
}
