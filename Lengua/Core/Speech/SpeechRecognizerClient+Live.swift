import AVFoundation
import Dependencies
import Foundation
import Speech

private typealias SpeechTranscriptStream = AsyncThrowingStream<SpeechRecognitionResult, Error>

extension SpeechRecognizerClient: DependencyKey {
  static var liveValue: SpeechRecognizerClient {
    let engine = SpeechRecognitionEngine()
    return SpeechRecognizerClient(
      authorizationStatus: { engine.currentAuthorizationStatus() },
      requestAuthorization: { await engine.requestAuthorization() },
      start: { localeIdentifier in try await engine.start(localeIdentifier: localeIdentifier) },
      stop: { await engine.stop() }
    )
  }
}

/// Owns the audio engine + recognition task. Vends a stream of transcripts and
/// tears everything down (including the record audio session) on stop / finish /
/// cancellation.
private final class SpeechRecognitionEngine {
  private typealias SpeechAuth = SFSpeechRecognizerAuthorizationStatus

  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var tapInstalled = false

  func currentAuthorizationStatus() -> SpeechAuthorizationStatus {
    let speech = Self.map(SFSpeechRecognizer.authorizationStatus())
    // Both speech recognition AND microphone permission are required; report the
    // more restrictive of the two so callers never see `.authorized` when the mic
    // is actually blocked.
    guard speech == .authorized else { return speech }
    switch AVAudioApplication.shared.recordPermission {
    case .granted: return .authorized
    case .denied: return .denied
    case .undetermined: return .notDetermined
    @unknown default: return .denied
    }
  }

  func requestAuthorization() async -> SpeechAuthorizationStatus {
    let speechStatus: SpeechAuth = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speechStatus == .authorized else { return Self.map(speechStatus) }
    let micGranted: Bool = await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
    }
    return micGranted ? .authorized : .denied
  }

  @MainActor
  fileprivate func start(localeIdentifier: String) async throws -> SpeechTranscriptStream {
    stopInternal()

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
      recognizer.isAvailable
    else {
      throw TranslatorError.translationFailed("Speech recognizer unavailable")
    }
    self.recognizer = recognizer

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.request = request

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    tapInstalled = true
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopInternal()
      throw error
    }

    return AsyncThrowingStream { continuation in
      self.task = recognizer.recognitionTask(with: request) { result, error in
        if let result {
          continuation.yield(
            SpeechRecognitionResult(
              transcript: result.bestTranscription.formattedString,
              isFinal: result.isFinal))
          if result.isFinal { continuation.finish() }
        }
        if let error {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.stopInternal() }
      }
    }
  }

  @MainActor
  func stop() {
    stopInternal()
  }

  @MainActor
  private func stopInternal() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    // Remove the tap based on whether we installed one, not on `isRunning`: if
    // `audioEngine.start()` threw after `installTap`, the engine isn't running but
    // the tap is still attached, and a second `installTap` on bus 0 would crash.
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    recognizer = nil
    // Release the record session so text-to-speech (which uses `.playback`) and
    // other apps can take over — but only if we still own it. Don't deactivate a
    // session another component has since taken with a different category.
    let session = AVAudioSession.sharedInstance()
    if session.category == .record {
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private static func map(_ status: SpeechAuth) -> SpeechAuthorizationStatus {
    switch status {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    case .authorized: .authorized
    @unknown default: .denied
    }
  }
}

// State is confined to the main actor via the @MainActor methods; the authorization
// helpers only touch framework globals. Conformance is declared here (not inline) so
// the class declaration stays lint-clean.
extension SpeechRecognitionEngine: @unchecked Sendable {}
