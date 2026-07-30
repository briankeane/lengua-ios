import SwiftUI

@MainActor
@Observable
final class TranslatePageModel: ViewModel {
  // MARK: - Properties
  var englishLabel: String { "English" }
  var englishPlaceholder: String { "Type or speak English" }
  var speakItHint: String { "Speak it" }
  var spanishLabel: String { "Spanish" }
  var spanishPlaceholder: String { "Spanish" }

  // MARK: - Initialization
  override init() { super.init() }

  // MARK: - User Actions
  func micButtonTapped() {}
  func swapButtonTapped() {}
  func speakerButtonTapped() {}
}

struct TranslatePage: View {
  @State var model: TranslatePageModel

  private let pageBlue = Color(red: 0.24, green: 0.29, blue: 0.85)
  private let deepBlue = Color(red: 0.15, green: 0.20, blue: 0.55)
  private let englishCardColor = Color(red: 0.98, green: 0.98, blue: 0.96)
  private let spanishCardColor = Color(red: 0.87, green: 0.89, blue: 0.98)

  var body: some View {
    ZStack {
      pageBlue.ignoresSafeArea()

      VStack(spacing: 0) {
        englishCard
        swapButton
          .padding(.vertical, -20)
          .zIndex(1)
        spanishCard
      }
      .padding(.horizontal, 16)
    }
  }

  private var englishCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.englishLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
      Text(model.englishPlaceholder)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Text(model.speakItHint)
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: model.micButtonTapped) {
          Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(pageBlue))
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20).fill(englishCardColor))
  }

  private var spanishCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.spanishLabel)
        .font(.subheadline).fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(deepBlue)
      Text(model.spanishPlaceholder)
        .font(.largeTitle).fontWeight(.semibold)
        .foregroundStyle(deepBlue.opacity(0.45))
      Spacer(minLength: 24)
      HStack(alignment: .bottom) {
        Spacer()
        Button(action: model.speakerButtonTapped) {
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
    .background(RoundedRectangle(cornerRadius: 20).fill(spanishCardColor))
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
