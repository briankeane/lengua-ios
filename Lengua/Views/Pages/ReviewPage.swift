import Dependencies
import Sharing
import SwiftUI

@MainActor
@Observable
final class ReviewPageModel: ViewModel {

  // MARK: - Dependencies
  @ObservationIgnored @Dependency(\.api) var api

  // MARK: - Shared State
  @ObservationIgnored @Shared(.vocabItems) var vocabItems

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - Properties
  enum ReviewMode: CaseIterable, Equatable, Hashable, Sendable {
    case adaptive
    case recognition
    case production
  }

  var mode: ReviewMode = .adaptive
  private(set) var dueCounts: DueCounts?
  private(set) var isLoading = false
  private(set) var loadFailed = false
  private(set) var session: ReviewSessionModel?

  private let sessionLimit = 20
  private let dueCountsProbeLimit = 1

  // MARK: - User Actions
  func viewAppeared() async {
    await refreshDueCounts()
  }

  func startReviewingButtonTapped() async {
    isLoading = true
    loadFailed = false
    do {
      let queue = try await api.getReviewQueue(direction, sessionLimit, nil)
      dueCounts = queue.dueCounts
      isLoading = false
      guard !queue.cards.isEmpty else { return }
      session = ReviewSessionModel(cards: queue.cards)
    } catch {
      isLoading = false
      loadFailed = true
    }
  }

  func retryButtonTapped() async {
    await refreshDueCounts()
  }

  func sessionFinished() async {
    session = nil
    await refreshDueCounts()
  }

  // MARK: - View Helpers
  var navigationTitle: String { "Review" }

  var direction: ReviewDirection? {
    switch mode {
    case .adaptive: return nil
    case .recognition: return .receptive
    case .production: return .productive
    }
  }

  var modes: [ReviewMode] { ReviewMode.allCases }

  func modeLabel(_ mode: ReviewMode) -> String {
    switch mode {
    case .adaptive: return "Adaptive"
    case .recognition: return "Recognition"
    case .production: return "Production"
    }
  }

  var modePickerLabel: String { "Review Mode" }

  var startButtonTitle: String { "Start Reviewing" }
  var retryButtonTitle: String { "Try Again" }
  var loadFailedText: String { "Something went wrong loading your review queue." }

  var totalDue: Int { dueCounts?.total ?? 0 }
  var noWordsSaved: Bool { vocabItems.items.isEmpty }
  var showsEmptyState: Bool { dueCounts != nil && totalDue == 0 }

  var dueSummary: String {
    guard let dueCounts, dueCounts.total > 0 else { return "All caught up 🎉" }
    return "\(dueCounts.receptive) to recognize · \(dueCounts.productive) to produce"
  }

  var emptyStateText: String {
    noWordsSaved
      ? "Save some words to review them here."
      : "You're all caught up — check back later."
  }

  // MARK: - Private Helpers
  private func refreshDueCounts() async {
    isLoading = true
    loadFailed = false
    do {
      let queue = try await api.getReviewQueue(nil, dueCountsProbeLimit, nil)
      dueCounts = queue.dueCounts
      isLoading = false
    } catch {
      isLoading = false
      loadFailed = true
    }
  }
}

struct ReviewPage: View {
  @State var model: ReviewPageModel

  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let cardColor = Color(red: 0.98, green: 0.98, blue: 0.96)

  var body: some View {
    ZStack {
      pageBlue.ignoresSafeArea()

      VStack(spacing: 16) {
        header
        content
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .task { await model.viewAppeared() }
    .fullScreenCover(
      isPresented: Binding(
        get: { model.session != nil },
        set: { if !$0 { Task { await model.sessionFinished() } } }
      )
    ) {
      if let session = model.session {
        ReviewSessionView(model: session, onDone: { Task { await model.sessionFinished() } })
      }
    }
  }

  private var header: some View {
    Text(model.navigationTitle)
      .font(.largeTitle).fontWeight(.bold)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var content: some View {
    if model.isLoading {
      Spacer()
      ProgressView().tint(.white)
      Spacer()
    } else if model.loadFailed {
      centeredMessage(model.loadFailedText) {
        Button(model.retryButtonTitle) { Task { await model.retryButtonTapped() } }
          .font(.headline)
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(deepBlue)
      }
    } else if model.showsEmptyState {
      centeredMessage(model.emptyStateText) { EmptyView() }
    } else {
      readyView
    }
  }

  private var readyView: some View {
    VStack(spacing: 24) {
      Spacer()
      Text(model.dueSummary)
        .font(.title3).fontWeight(.semibold)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      Picker(model.modePickerLabel, selection: $model.mode) {
        ForEach(model.modes, id: \.self) { mode in
          Text(model.modeLabel(mode)).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      startButton
      Spacer()
    }
  }

  private var startButton: some View {
    Button {
      Task { await model.startReviewingButtonTapped() }
    } label: {
      Text(model.startButtonTitle)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Capsule().fill(deepBlue))
    }
  }

  private func centeredMessage<Action: View>(
    _ text: String, @ViewBuilder action: () -> Action
  ) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "rectangle.stack")
        .font(.system(size: 44))
        .foregroundStyle(.white.opacity(0.7))
      Text(text)
        .font(.body)
        .foregroundStyle(.white.opacity(0.85))
        .multilineTextAlignment(.center)
      action()
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}
