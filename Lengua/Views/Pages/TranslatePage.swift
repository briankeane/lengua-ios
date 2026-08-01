import Dependencies
import SwiftUI

@MainActor
@Observable
final class TranslatePageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.translator) var translator
  @ObservationIgnored @Dependency(\.continuousClock) var clock
  @ObservationIgnored @Dependency(\.speechSynthesizer) var speechSynthesizer
  @ObservationIgnored @Dependency(\.speechRecognizer) var speechRecognizer

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var direction: TranslationDirection = .englishToSpanish
  var inputText = "" {
    didSet {
      guard inputText != oldValue else { return }
      scheduleTranslation()
    }
  }
  var outputText = ""
  var isTranslating = false
  var isRecording = false
  var presentedAlert: LenguaAlert?

  @ObservationIgnored private(set) var translationTask: Task<Void, Never>?
  @ObservationIgnored private(set) var recognitionTask: Task<Void, Never>?

  // MARK: - User Actions
  func swapButtonTapped() {
    translationTask?.cancel()
    // Stop dictation: it was started for the old direction's locale, so continuing
    // would feed the wrong language into the newly-flipped direction.
    recognitionTask?.cancel()
    direction.toggle()
    let previousInput = inputText
    inputText = outputText  // didSet schedules a fresh translation
    outputText = previousInput  // show the swapped text immediately
  }

  func pageDisappeared() {
    // Cancel any in-flight/debouncing translation so a request that fails while
    // the user is on another tab can't set `presentedAlert` and surface a stale
    // "Translation Failed" alert when they return. Also stop dictation so the mic
    // and record audio session are released when leaving the tab.
    translationTask?.cancel()
    recognitionTask?.cancel()
    // Stop any in-progress speech so it doesn't keep the playback audio session
    // active after we've left the tab.
    Task { await speechSynthesizer.stop() }
  }

  func speakerButtonTapped() async {
    guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    // Serialize with dictation: stop the recognizer (and let its .record session
    // tear down) before TTS takes the shared audio session with .playback.
    recognitionTask?.cancel()
    await recognitionTask?.value
    do {
      try await speechSynthesizer.speak(outputText, direction.speechSynthesisLanguageIdentifier)
    } catch {
      presentedAlert = .speechSynthesisFailed
    }
  }

  func micButtonTapped() {
    if isRecording {
      recognitionTask?.cancel()
      return
    }
    // Set `isRecording` synchronously so a second tap toggles off instead of
    // starting a second recognition task (which would fight for the mic).
    isRecording = true
    recognitionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { isRecording = false }
      let status = await speechRecognizer.requestAuthorization()
      // The permission prompt is an async suspension point: if a second tap or
      // `pageDisappeared()` cancelled us while it was up, bail before turning on
      // the mic (and before surfacing a denial alert on a page we've left).
      guard !Task.isCancelled else { return }
      guard status == .authorized else {
        presentedAlert = .speechRecognitionPermissionDenied
        return
      }
      // Serialize with TTS: release its .playback session before we take the mic's
      // .record session so the two never fight over the shared audio session.
      await speechSynthesizer.stop()
      guard !Task.isCancelled else { return }
      do {
        let stream = try await speechRecognizer.start(direction.speechRecognitionLocaleIdentifier)
        for try await result in stream {
          inputText = result.transcript  // drives auto-translate via didSet
        }
      } catch is CancellationError {
      } catch {
        // A cancelled recognizer often reports a framework error rather than a
        // CancellationError; don't surface a failure alert for a deliberate stop.
        guard !Task.isCancelled else { return }
        presentedAlert = .speechRecognitionFailed
      }
      await speechRecognizer.stop()
    }
  }

  // MARK: - View Helpers
  var inputLabel: String { direction.inputLabel }
  var outputLabel: String { direction.outputLabel }
  var inputPlaceholder: String {
    switch direction {
    case .englishToSpanish: "Type or speak English"
    case .spanishToEnglish: "Type or speak Spanish"
    }
  }
  var outputPlaceholder: String { direction.outputLabel }
  var outputIsPlaceholder: Bool { outputText.isEmpty }
  var outputDisplayText: String { outputText.isEmpty ? outputPlaceholder : outputText }
  var speakItHint: String { "Speak it" }

  // MARK: - Private Helpers
  private func scheduleTranslation() {
    translationTask?.cancel()
    let text = inputText
    let currentDirection = direction

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      outputText = ""
      isTranslating = false
      return
    }

    isTranslating = true
    translationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await clock.sleep(for: .milliseconds(500))
        try Task.checkCancellation()
        let translated = try await translator.translate(text, currentDirection)
        try Task.checkCancellation()
        // Ignore stale results: a newer edit/swap owns the state now.
        guard inputText == text, direction == currentDirection else { return }
        outputText = translated
        isTranslating = false
      } catch is CancellationError {
        // Superseded by a newer schedule, which owns `isTranslating`.
      } catch {
        guard inputText == text, direction == currentDirection else { return }
        outputText = ""
        isTranslating = false
        presentedAlert = .translationFailed
      }
    }
  }
}

struct TranslatePage: View {
  @State var model: TranslatePageModel

  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let inputCardColor = Color(red: 0.98, green: 0.98, blue: 0.96)
  private let outputCardColor = Color(red: 0.87, green: 0.89, blue: 0.98)

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          inputCard
          swapButton
            .padding(.vertical, -20)
            .zIndex(1)
          outputCard
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
    }
    .background(pageBlue.ignoresSafeArea())
    .lenguaAlert($model.presentedAlert)
    .onDisappear { model.pageDisappeared() }
  }

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.inputLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
      TextField(model.inputPlaceholder, text: $model.inputText, axis: .vertical)
        .font(.largeTitle)
        .foregroundStyle(.primary)
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Text(model.speakItHint)
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: model.micButtonTapped) {
          Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(model.isRecording ? deepBlue : pageBlue))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20).fill(inputCardColor))
  }

  private var outputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.outputLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(deepBlue)
      Text(model.outputDisplayText)
        .font(.largeTitle).fontWeight(.semibold)
        .foregroundStyle(model.outputIsPlaceholder ? deepBlue.opacity(0.45) : deepBlue)
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Spacer()
        Button {
          Task { await model.speakerButtonTapped() }
        } label: {
          Image(systemName: "speaker.wave.2.fill")
            .font(.title2)
            .foregroundStyle(deepBlue)
            .frame(width: 56, height: 56)
            .background(Circle().stroke(deepBlue.opacity(0.3), lineWidth: 1))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20).fill(outputCardColor))
  }

  private var swapButton: some View {
    Button(action: model.swapButtonTapped) {
      Image(systemName: "arrow.up.arrow.down")
        .font(.headline)
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(Circle().fill(deepBlue))
    }
  }
}
