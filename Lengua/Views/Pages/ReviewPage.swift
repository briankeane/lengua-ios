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

  var startButtonTitle: String { "Start Reviewing" }
  var retryButtonTitle: String { "Try Again" }

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

  var body: some View {
    Text(model.navigationTitle)
      .font(.largeTitle)
      .navigationTitle(model.navigationTitle)
  }
}
