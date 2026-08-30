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
  var compactInputHint: String {
    isRecording ? "Listening · \(formattedRecordingTime)" : "Type or speak"
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

/// The two visual states of the Look Up screen. `expanded` is the default
/// (keyboard down); `compact` shrinks everything to sit above the iOS keyboard
/// while the input is focused. Same view skeleton in both — only these metrics
/// and a few chrome choices differ.
private struct TranslateLayoutMetrics {
  var titleFont: Font
  var subtitleFont: Font
  var cardOuterRadius: CGFloat
  var cardBodyFont: Font
  var cardPadding: CGFloat
  var cardSpacing: CGFloat
  var cardMinHeight: CGFloat
  var hintFontSize: CGFloat
  var actionSize: CGFloat
  var iconSize: CGFloat
  var seamOverlap: CGFloat
  var saveHeight: CGFloat
  var saveFont: Font
  var contentSpacing: CGFloat
  var contentPadding: EdgeInsets

  static let expanded = TranslateLayoutMetrics(
    titleFont: .funnel(32, weight: .bold),
    subtitleFont: .inter(13),
    cardOuterRadius: 20,
    cardBodyFont: .funnel(30, weight: .bold),
    cardPadding: 20,
    cardSpacing: 12,
    cardMinHeight: 240,
    hintFontSize: 14,
    actionSize: 48,
    iconSize: 20,
    seamOverlap: 4,
    saveHeight: 54,
    saveFont: .inter(17, weight: .semibold),
    contentSpacing: 14,
    contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))

  static let compact = TranslateLayoutMetrics(
    titleFont: .funnel(24, weight: .bold),
    subtitleFont: .inter(12),
    cardOuterRadius: 16,
    cardBodyFont: .funnel(24, weight: .bold),
    cardPadding: 14,
    cardSpacing: 6,
    cardMinHeight: 150,
    hintFontSize: 12,
    actionSize: 44,
    iconSize: 18,
    seamOverlap: 4,
    saveHeight: 46,
    saveFont: .inter(15, weight: .bold),
    contentSpacing: 10,
    contentPadding: EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
}

struct TranslatePage: View {
  @State var model: TranslatePageModel
  @FocusState private var isInputFocused: Bool
  @State private var isCompact = false

  private var metrics: TranslateLayoutMetrics {
    isCompact ? .compact : .expanded
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        content
          .padding(metrics.contentPadding)
          .frame(
            maxWidth: .infinity,
            minHeight: isCompact ? 0 : proxy.size.height,
            alignment: .top)
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
    .onChange(of: isInputFocused) { _, focused in
      // Match the iOS keyboard's show/hide timing so the layout shrinks and grows
      // in lockstep with the keyboard sliding in and out.
      withAnimation(.easeInOut(duration: 0.25)) { isCompact = focused }
    }
    .task { await model.pageAppeared() }
    .onDisappear { model.pageDisappeared() }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: metrics.contentSpacing) {
      header
      cardStack
      saveButton
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.pageTitle)
          .font(metrics.titleFont)
          .foregroundStyle(.white)
        Text(model.directionSubtitle)
          .font(metrics.subtitleFont)
          .foregroundStyle(.white.opacity(0.75))
      }
      Spacer()
      headerTrailingAction
    }
  }

  @ViewBuilder private var headerTrailingAction: some View {
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

  /// Input and output cards butted together at a seam, with the swap control
  /// floating centered over that seam.
  private var cardStack: some View {
    VStack(spacing: -metrics.seamOverlap) {
      inputCard
        .overlay(alignment: .bottom) {
          swapButton.offset(y: metrics.actionSize / 2)
        }
        .zIndex(1)
      outputCard
    }
  }

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: metrics.cardSpacing) {
      HStack {
        Text(model.inputLabel)
          .font(.inter(12, weight: .bold))
          .textCase(.uppercase)
          .foregroundStyle(Color.muted)
        Spacer()
        if isCompact {
          Button {
            model.clearButtonTapped()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Color.brandDeep)
              .frame(width: metrics.actionSize, height: metrics.actionSize)
              .background(Circle().fill(Color.brandSoft))
          }
        }
      }
      TextField(model.inputPlaceholder, text: $model.inputText, axis: .vertical)
        .font(metrics.cardBodyFont)
        .foregroundStyle(Color.ink)
        .focused($isInputFocused)
      Spacer(minLength: metrics.cardSpacing)
      HStack(alignment: .bottom) {
        Text(isCompact ? model.compactInputHint : model.inputHint)
          .font(.inter(metrics.hintFontSize, weight: model.isRecording ? .bold : .regular))
          .foregroundStyle(model.isRecording ? Color.danger : Color.muted)
        Spacer()
        micButton
      }
    }
    .padding(metrics.cardPadding)
    .frame(maxWidth: .infinity, minHeight: metrics.cardMinHeight, alignment: .topLeading)
    .background(cardShape(topRadius: metrics.cardOuterRadius, bottomRadius: 4).fill(Color.surface))
  }

  private var outputCard: some View {
    VStack(alignment: .leading, spacing: metrics.cardSpacing) {
      HStack {
        Text(model.outputStatusLabel)
          .font(.inter(12, weight: .bold))
          .foregroundStyle(Color.brandDeep)
        Spacer()
        if isCompact { speakerButton }
      }
      if model.showsDownloadPrompt {
        downloadPrompt
      } else {
        Text(model.outputBodyText)
          .font(metrics.cardBodyFont)
          .foregroundStyle(Color.brandDeep.opacity(outputBodyOpacity))
      }
      if !isCompact {
        Spacer(minLength: metrics.cardSpacing)
        HStack(alignment: .bottom) {
          Text(model.outputHint)
            .font(.inter(14))
            .foregroundStyle(Color.brandDeep)
          Spacer()
          speakerButton
        }
      }
    }
    .padding(metrics.cardPadding)
    .frame(maxWidth: .infinity, minHeight: metrics.cardMinHeight, alignment: .topLeading)
    .background(
      cardShape(topRadius: 4, bottomRadius: metrics.cardOuterRadius).fill(Color.brandSoft))
  }

  private var micButton: some View {
    Button(action: model.micButtonTapped) {
      Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
        .font(.system(size: metrics.iconSize, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: metrics.actionSize, height: metrics.actionSize)
        .background(Circle().fill(micColor))
    }
  }

  private var micColor: Color {
    if model.isRecording { return .danger }
    return isCompact ? .brand : .brandDeep
  }

  /// Filled circle in expanded state, ghost/outline in compact state.
  private var speakerButton: some View {
    Button {
      Task { await model.speakerButtonTapped() }
    } label: {
      speakerGlyph
        .frame(width: metrics.actionSize, height: metrics.actionSize)
        .background(speakerBackground)
    }
    .disabled(model.isTranslating)
  }

  @ViewBuilder private var speakerGlyph: some View {
    if model.isTranslating {
      ProgressView().tint(isCompact ? Color.brandDeep : .white)
    } else {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: metrics.iconSize, weight: .semibold))
        .foregroundStyle(isCompact ? Color.brandDeep : .white)
    }
  }

  @ViewBuilder private var speakerBackground: some View {
    if isCompact {
      Circle().stroke(Color.brandDeep, lineWidth: 1.5)
    } else {
      Circle().fill(Color.brandDeep)
    }
  }

  private var swapButton: some View {
    Button(action: model.swapButtonTapped) {
      Image(systemName: "arrow.up.arrow.down")
        .font(.system(size: metrics.iconSize, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: metrics.actionSize, height: metrics.actionSize)
        .background(Circle().fill(Color.brandDeep))
    }
  }

  private var saveButton: some View {
    Button {
      Task { await model.saveButtonTapped() }
    } label: {
      Text(model.saveButtonTitle)
        .font(metrics.saveFont)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.saveHeight)
        .background(Capsule().fill(Color.brandDeep))
    }
    .disabled(!model.isSaveEnabled)
    .opacity(model.isSaveEnabled ? 1 : 0.42)
  }

  private var outputBodyOpacity: Double {
    if model.isTranslating { return 0.55 }
    if model.outputIsPlaceholder { return 0.45 }
    return 1
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

  private func cardShape(topRadius: CGFloat, bottomRadius: CGFloat) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: topRadius,
      bottomLeadingRadius: bottomRadius,
      bottomTrailingRadius: bottomRadius,
      topTrailingRadius: topRadius)
  }
}
