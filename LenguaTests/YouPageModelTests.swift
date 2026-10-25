import ConcurrencyExtras
import CustomDump
import Dependencies
import Sharing
import Testing

@testable import Lengua

@MainActor
@Suite(.serialized, .isolatedSharedState)
struct YouPageModelTests {
  /// Runs `body` with `defaultAppStorage` overridden to a fresh in-memory
  /// `UserDefaults`, so any `@Shared(.translationProviderKind)` touched inside
  /// is quarantined from the real `UserDefaults.standard`. See the identical
  /// helper in `TranslationProviderTests` for the full rationale.
  private func withInMemoryAppStorage<T>(_ body: () throws -> T) rethrows -> T {
    try withDependencies {
      $0.defaultAppStorage = .inMemory
    } operation: {
      try body()
    }
  }

  @Test func titleIsYou() {
    withInMemoryAppStorage {
      let model = YouPageModel()
      expectNoDifference(model.title, "You")
    }
  }

  @Test func signOutButtonTitleIsSignOut() {
    withInMemoryAppStorage {
      let model = YouPageModel()
      expectNoDifference(model.signOutButtonTitle, "Sign Out")
    }
  }

  @Test func displayNameAndEmailReflectCurrentUser() {
    withInMemoryAppStorage {
      @Shared(.auth) var auth = Auth(
        jwtToken: "t",
        currentUser: User(
          id: "1", email: "a@b.com", firstName: "Sam", lastName: nil, profileImageUrl: nil))
      let model = YouPageModel()
      expectNoDifference(model.displayName, "Sam")
      expectNoDifference(model.emailText, "a@b.com")
    }
  }

  @Test func displayNameFallsBackWhenNoName() {
    withInMemoryAppStorage {
      @Shared(.auth) var auth = Auth()
      let model = YouPageModel()
      expectNoDifference(model.displayName, "Signed in")
      #expect(model.emailText == nil)
    }
  }

  @Test func signOutButtonTappedCallsAuthClientSignOut() async {
    @Shared(.auth) var auth = Auth(jwtToken: "t")
    let signedOut = LockIsolated(false)
    let model = withDependencies {
      $0.defaultAppStorage = .inMemory
      $0.authClient.signOut = { signedOut.setValue(true) }
    } operation: {
      YouPageModel()
    }

    await model.signOutButtonTapped()

    #expect(signedOut.value)
  }

  @Test func providerSectionTitleIsTranslationProvider() {
    withInMemoryAppStorage {
      @Shared(.translationProviderKind) var kind = .apple
      let model = YouPageModel()
      expectNoDifference(model.providerSectionTitle, "Translation Provider")
    }
  }

  @Test func providerOptionsMarkSelectedAndDisabled() {
    withInMemoryAppStorage {
      @Shared(.translationProviderKind) var kind = .apple
      let model = YouPageModel()
      let options = model.providerOptions
      expectNoDifference(options.map(\.name), ["Apple", "DeepL"])

      let apple = options.first { $0.kind == .apple }
      let deepL = options.first { $0.kind == .deepL }
      #expect(apple?.isSelected == true)
      #expect(apple?.isEnabled == true)
      #expect(apple?.disabledNote == nil)
      #expect(deepL?.isSelected == false)
      #expect(deepL?.isEnabled == false)
      expectNoDifference(deepL?.disabledNote, "Coming soon")
    }
  }

  @Test func selectingEnabledProviderPersistsChoice() {
    withInMemoryAppStorage {
      @Shared(.translationProviderKind) var kind = .deepL  // start off-default
      let model = YouPageModel()
      model.selectProvider(.apple)
      expectNoDifference(kind, .apple)
      #expect(model.providerOptions.first { $0.kind == .apple }?.isSelected == true)
    }
  }

  @Test func selectingDisabledProviderIsIgnored() {
    withInMemoryAppStorage {
      @Shared(.translationProviderKind) var kind = .apple
      let model = YouPageModel()
      model.selectProvider(.deepL)
      expectNoDifference(kind, .apple)  // unchanged — DeepL is disabled
    }
  }
}
