import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class TranslatePageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api
  @ObservationIgnored @Dependency(\.translator) var translator
  @ObservationIgnored @Dependency(\.continuousClock) var clock
  @ObservationIgnored @Dependency(\.speechSynthesizer) var speechSynthesizer
  @ObservationIgnored @Dependency(\.speechRecognizer) var speechRecognizer

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems
  @ObservationIgnored @Shared(.auth) var auth

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  var direction: TranslationDirection = .englishToSpanish
  var inputText = "" {
    didSet {
      guard inputText != oldValue else { return }
      // Editing the source makes the visible pair unsaved, even if the eventual
      // translation happens to produce the same output text.
      saveState = .idle
      scheduleTranslation()
    }
  }
  var outputText = "" {
    didSet {
      guard outputText != oldValue else { return }
      // Any new translation content is unsaved: clear a prior "Saved" state.
      saveState = .idle
    }
  }
  var isTranslating = false
  var isRecording = false
  var recordingElapsed = 0
  var saveState: SaveState = .idle
  var presentedAlert: LenguaAlert?

  enum SaveState: Equatable { case idle, saving, saved }

  /// The direction whose on-device model still needs downloading. When it equals
  /// the current `direction`, the output card shows the download affordance
  /// instead of going blank. `nil` once the model is installed.
  var downloadRequiredDirection: TranslationDirection?
  /// True while a download provoke is in flight — the manual gate that stops a
  /// second Download tap from stacking another system sheet.
  var isPreparingDownload = false

  @ObservationIgnored private(set) var translationTask: Task<Void, Never>?
  @ObservationIgnored private(set) var recognitionTask: Task<Void, Never>?
  @ObservationIgnored private(set) var recordingTimerTask: Task<Void, Never>?
  @ObservationIgnored private(set) var downloadTask: Task<Void, Never>?
  /// Directions already auto-prompted this model lifetime. The auto gate: the
  /// sheet is auto-provoked at most once per direction, so a dismissal never
  /// re-pops it on its own — only the Download button (user intent) does.
  @ObservationIgnored private var autoPromptedDownloadDirections: Set<TranslationDirection> = []

  // MARK: - User Actions
  func pageAppeared() async {
    await refreshTranslationAvailability()
  }

  func swapButtonTapped() {
    translationTask?.cancel()
    // Stop dictation: it was started for the old direction's locale, so continuing
    // would feed the wrong language into the newly-flipped direction.
    recognitionTask?.cancel()
    direction.toggle()
    // The new direction has its own model-availability; drop any stale prompt so
    // the flipped direction is re-evaluated by the fresh translation below.
    downloadRequiredDirection = nil
    let previousInput = inputText
    inputText = outputText  // didSet schedules a fresh translation
    outputText = previousInput  // show the swapped text immediately
  }

  func clearButtonTapped() {
    translationTask?.cancel()
    recognitionTask?.cancel()
    inputText = ""
    outputText = ""
    saveState = .idle
  }

  func downloadButtonTapped() {
    // Gate synchronously so a rapid second tap neither stacks a second provoke
    // nor overwrites `downloadTask` (which would orphan the live task and defeat
    // cancel-on-disappear). `isPreparingDownload` is set here and cleared by
    // `provokeDownload`'s defer. We deliberately do NOT cancel an in-flight
    // provoke on re-tap — that could interrupt the system sheet mid-interaction.
    guard !isPreparingDownload else { return }
    isPreparingDownload = true
    let provokeDirection = direction
    downloadTask = Task { @MainActor [weak self] in
      await self?.provokeDownload(for: provokeDirection)
    }
  }

  func pageDisappeared() {
    // Cancel any in-flight/debouncing translation so a request that fails while
    // the user is on another tab can't set `presentedAlert` and surface a stale
    // "Translation Failed" alert when they return. Also cancel a manual download
    // provoke so it can't mutate prompt/alert state after we've left the tab.
    // (The auto-provoke on appear rides SwiftUI's `.task`, which cancels itself.)
    // Also stop dictation so the mic and record audio session are released.
    translationTask?.cancel()
    recognitionTask?.cancel()
    downloadTask?.cancel()
    // Stop any in-progress speech so it doesn't keep the playback audio session
    // active after we've left the tab.
    Task { await speechSynthesizer.stop() }
  }

  func saveButtonTapped() async {
    guard saveState == .idle, !isTranslating, let request = currentSaveRequest else { return }

    saveState = .saving
    let startingToken = auth.jwtToken  // bind this save to the current account
    do {
      let item = try await api.saveVocabItem(request)
      // Reflect the saved item in the shared library, but only if the same
      // account that started the save is still signed in: a sign-out or
      // account switch mid-save must not leak the item into another session.
      if auth.jwtToken == startingToken {
        $vocabItems.withLock { $0.items[id: item.id] = item }
      }
      // Ignore the *button* state if the user edited, swapped, or changed
      // direction mid-save: the visible term no longer matches what we saved.
      guard currentSaveRequest == request else { return }
      saveState = .saved
    } catch {
      guard currentSaveRequest == request else { return }
      saveState = .idle
      if case APIError.unauthorized = error {
        presentedAlert = .saveRequiresSignIn
      } else {
        presentedAlert = .saveFailed
      }
    }
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
      defer {
        isRecording = false
        recordingTimerTask?.cancel()
      }
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
      // Start the elapsed timer only once dictation is actually about to begin, so
      // it never counts time spent on the (first-use) permission prompt.
      startRecordingTimer()
      do {
        let stream = try await speechRecognizer.start(direction.speechRecognitionLocaleIdentifier)
        for try await result in stream {
          // A buffered transcript can arrive after cancellation (e.g. the learner
          // tapped Clear or left the page); don't let it repopulate the cleared input.
          guard !Task.isCancelled else { break }
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

  // MARK: - Private Helpers
  private var formattedRecordingTime: String {
    String(format: "%d:%02d", recordingElapsed / 60, recordingElapsed % 60)
  }

  private func startRecordingTimer() {
    recordingTimerTask?.cancel()
    recordingElapsed = 0
    recordingTimerTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do { try await clock.sleep(for: .seconds(1)) } catch { return }
        recordingElapsed += 1
      }
    }
  }

  /// The save request for the currently-visible term, or `nil` when there is
  /// nothing to save. Used as an identity to detect edits/swaps mid-save.
  private var currentSaveRequest: SaveVocabItemRequest? {
    let sourceText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetText = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceText.isEmpty, !targetText.isEmpty else { return nil }
    return SaveVocabItemRequest(
      targetLanguageCode: direction.targetLanguageCode,
      sourceText: sourceText,
      targetText: targetText)
  }

  private func scheduleTranslation() {
    translationTask?.cancel()
    let text = inputText
    let currentDirection = direction

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      outputText = ""
      isTranslating = false
      return
    }

    // While the current direction's model needs downloading, do not auto-translate:
    // a translate re-provokes the system download sheet, so every keystroke would
    // re-pop it. The Download button is the one intentional way to re-provoke.
    // `provokeDownload`/`refreshTranslationAvailability` clear
    // `downloadRequiredDirection` before scheduling, so translation resumes once
    // the model is installed.
    guard downloadRequiredDirection != currentDirection else {
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
        // A successful translation means the model is installed; retire any prompt.
        if downloadRequiredDirection == currentDirection { downloadRequiredDirection = nil }
      } catch is CancellationError {
        // Superseded by a newer schedule, which owns `isTranslating`.
      } catch TranslatorError.downloadRequired {
        // The model isn't downloaded (e.g. the user dismissed the system sheet).
        // Surface the download affordance instead of a dead-end failure alert.
        guard inputText == text, direction == currentDirection else { return }
        outputText = ""
        isTranslating = false
        downloadRequiredDirection = currentDirection
      } catch {
        guard inputText == text, direction == currentDirection else { return }
        outputText = ""
        isTranslating = false
        presentedAlert = .translationFailed
      }
    }
  }

  /// Queries the current direction's model availability and, if it needs
  /// downloading, shows the affordance and auto-provokes the system sheet once
  /// per direction. Called on page appear. `.unknown` (e.g. the Simulator) and
  /// `.unsupported` do nothing — never auto-loop.
  private func refreshTranslationAvailability() async {
    let currentDirection = direction
    let availability = await translator.availability(currentDirection)
    // The availability query is a suspension point; if the direction changed (or
    // the page went away) while it was in flight, this result is stale — dropping
    // it avoids prompting or provoking a sheet for a direction the user has left.
    guard !Task.isCancelled, direction == currentDirection else { return }
    switch availability {
    case .installed:
      // The model became available (e.g. downloaded elsewhere); retire the prompt
      // and translate the pending input so the output is no longer blank.
      guard downloadRequiredDirection == currentDirection else { return }
      downloadRequiredDirection = nil
      if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        scheduleTranslation()
      }
    case .downloadRequired:
      downloadRequiredDirection = currentDirection
      // Auto-provoke once per direction, and only when no provoke is already in
      // flight. Set the gate before provoking so it owns the same
      // `isPreparingDownload` lifecycle as the manual button.
      guard !isPreparingDownload,
        autoPromptedDownloadDirections.insert(currentDirection).inserted
      else { return }
      isPreparingDownload = true
      await provokeDownload(for: currentDirection)
    case .unsupported, .unknown:
      break
    }
  }

  /// Provokes the system download sheet for `provokeDirection`. On success the
  /// prompt is retired and the pending input re-translated; on a repeat
  /// `.downloadRequired` (user dismissed again) the prompt simply stays — it is
  /// never auto-re-provoked here, which is what avoids an infinite sheet loop.
  /// Guards `direction == provokeDirection` (and cancellation) before every
  /// mutation so a direction flip or page-leave mid-download can't clobber state.
  ///
  /// Callers (the Download button and the auto-provoke) set `isPreparingDownload`
  /// before invoking; this owns clearing it.
  private func provokeDownload(for provokeDirection: TranslationDirection) async {
    defer { isPreparingDownload = false }
    do {
      try await translator.prepareTranslation(provokeDirection)
      guard !Task.isCancelled, direction == provokeDirection else { return }
      downloadRequiredDirection = nil
      if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        scheduleTranslation()
      }
    } catch is CancellationError {
    } catch TranslatorError.downloadRequired {
      guard direction == provokeDirection else { return }
      downloadRequiredDirection = provokeDirection
    } catch {
      guard direction == provokeDirection else { return }
      // Keep the affordance if the model is genuinely still missing; otherwise
      // this was a real failure worth surfacing.
      let stillMissing = await translator.availability(provokeDirection) == .downloadRequired
      // Re-check after the availability suspension point: a direction flip (or a
      // cancelled download task on page leave) mid-await must not write stale state.
      guard !Task.isCancelled, direction == provokeDirection else { return }
      if stillMissing {
        downloadRequiredDirection = provokeDirection
      } else {
        presentedAlert = .translationFailed
      }
    }
  }
}

// MARK: - View Helpers
extension TranslatePageModel {
  var pageTitle: String { "Look up" }
  var directionSubtitle: String { "\(direction.inputLabel) → \(direction.outputLabel)" }
  var clearButtonTitle: String { "Clear" }
  var isClearVisible: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var inputLabel: String { direction.inputLabel }
  var outputLabel: String { direction.outputLabel }
  var inputPlaceholder: String {
    switch direction {
    case .englishToSpanish: "Type or speak English"
    case .spanishToEnglish: "Type or speak Spanish"
    }
  }
  var inputHint: String {
    isRecording ? "Listening · \(formattedRecordingTime)" : "Tap the mic to speak"
  }

  var outputPlaceholder: String { direction.outputLabel }
  var outputIsPlaceholder: Bool { outputText.isEmpty }
  var outputDisplayText: String { outputText.isEmpty ? outputPlaceholder : outputText }
  var outputStatusLabel: String {
    let base = direction.outputLabel.uppercased()
    if isTranslating { return "\(base) · TRANSLATING…" }
    if !outputText.isEmpty { return "\(base) · READY" }
    return base
  }
  var outputBodyText: String {
    isTranslating ? "Translating your phrase…" : outputDisplayText
  }
  var outputHint: String {
    isTranslating ? "Working on device" : "Listen"
  }

  var doneButtonTitle: String { "Done" }
  var saveButtonTitle: String {
    if isTranslating { return "Translating…" }
    switch saveState {
    case .idle: return "Save to Library"
    case .saving: return "Saving…"
    case .saved: return "Saved"
    }
  }
  var isSaveEnabled: Bool {
    // `isTranslating` guards the stale window: after editing the source, the old
    // output is still visible until retranslation lands, and saving then would
    // persist the new source paired with the previous target.
    saveState == .idle && !isTranslating
      && !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Whether to show the download affordance in place of the (blank) output —
  /// true only when the current direction's model needs downloading.
  var showsDownloadPrompt: Bool { downloadRequiredDirection == direction }
  var downloadPromptText: String {
    "\(direction.outputLabel) translation needs to be downloaded."
  }
  var downloadButtonTitle: String { "Download" }
}

struct TranslatePage: View {
  @State var model: TranslatePageModel
  @FocusState private var isInputFocused: Bool

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          header
          inputCard
          swapRow
          outputCard
          saveButton
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Color.brand.ignoresSafeArea())
    .lenguaAlert($model.presentedAlert)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(model.doneButtonTitle) { isInputFocused = false }
      }
    }
    .task { await model.pageAppeared() }
    .onDisappear { model.pageDisappeared() }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.pageTitle)
          .font(.funnel(32, weight: .bold))
          .foregroundStyle(.white)
        Text(model.directionSubtitle)
          .font(.inter(13))
          .foregroundStyle(.white.opacity(0.73))
      }
      Spacer()
      if model.isClearVisible {
        Button {
          model.clearButtonTapped()
        } label: {
          Text(model.clearButtonTitle)
            .font(.inter(12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Color.white.opacity(0.133)))
        }
      }
    }
  }

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.inputLabel)
        .font(.inter(12, weight: .bold))
        .textCase(.uppercase)
        .foregroundStyle(Color.muted)
      TextField(model.inputPlaceholder, text: $model.inputText, axis: .vertical)
        .font(.funnel(27, weight: .bold))
        .foregroundStyle(Color.ink)
        .focused($isInputFocused)
      Spacer(minLength: 12)
      HStack(alignment: .bottom) {
        Text(model.inputHint)
          .font(.inter(14, weight: model.isRecording ? .bold : .regular))
          .foregroundStyle(model.isRecording ? Color.danger : Color.muted)
        Spacer()
        Button(action: model.micButtonTapped) {
          Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(model.isRecording ? Color.danger : Color.brandDeep))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: DesignRadius.card).fill(Color.surface))
  }

  private var outputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.outputStatusLabel)
        .font(.inter(12, weight: .bold))
        .foregroundStyle(Color.brandDeep)
      if model.showsDownloadPrompt {
        downloadPrompt
      } else {
        Text(model.outputBodyText)
          .font(.funnel(model.isTranslating ? 24 : 27, weight: .bold))
          .foregroundStyle(Color.brandDeep.opacity(outputBodyOpacity))
      }
      Spacer(minLength: 12)
      HStack(alignment: .bottom) {
        Text(model.outputHint)
          .font(.inter(14))
          .foregroundStyle(Color.brandDeep)
        Spacer()
        Button {
          Task { await model.speakerButtonTapped() }
        } label: {
          outputActionGlyph
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.brandDeep))
        }
        .disabled(model.isTranslating)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: DesignRadius.card).fill(Color.brandSoft))
  }

  private var outputBodyOpacity: Double {
    if model.isTranslating { return 0.55 }
    if model.outputIsPlaceholder { return 0.45 }
    return 1
  }

  @ViewBuilder private var outputActionGlyph: some View {
    if model.isTranslating {
      ProgressView().tint(.white)
    } else {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
    }
  }

  private var downloadPrompt: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.downloadPromptText)
        .font(.funnel(20, weight: .bold))
        .foregroundStyle(Color.brandDeep)
      Button {
        model.downloadButtonTapped()
      } label: {
        Text(model.downloadButtonTitle)
          .font(.inter(15, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(Capsule().fill(Color.brandDeep))
      }
      .disabled(model.isPreparingDownload)
    }
  }

  private var swapRow: some View {
    HStack {
      Spacer()
      Button(action: model.swapButtonTapped) {
        Image(systemName: "arrow.up.arrow.down")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(Circle().fill(Color.brandDeep))
      }
      Spacer()
    }
  }

  private var saveButton: some View {
    Button {
      Task { await model.saveButtonTapped() }
    } label: {
      Text(model.saveButtonTitle)
        .font(.inter(17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Capsule().fill(Color.brandDeep))
    }
    .disabled(!model.isSaveEnabled)
    .opacity(model.isSaveEnabled ? 1 : 0.42)
  }
}
