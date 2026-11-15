//
//  AuthModelTests.swift
//  Auth
//
//  Created by Guilherme Souza on 04/11/26.
//

#if canImport(Observation)
  import ConcurrencyExtras
  import Foundation
  import Helpers
  import Observation
  import TestHelpers
  import Testing

  @testable import Auth

  @MainActor
  @Suite struct AuthModelTests {
    let sut = AuthClient.testing(http: RecordingTransport())

    private var store: SessionStore { sut.dependencies.sessionStore }

    @Test
    func staysLoadingWhileStorageIsLockedThenMirrorsTheInitialSession() async throws {
      guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }

      let storage = LockedLocalStorage()
      storage.isLocked.setValue(true)
      let client = AuthClient.testing(http: RecordingTransport(), storage: storage)

      let model = AuthModel(client: client)

      #expect(model.status == .loading)
      #expect(model.isLoading)
      #expect(model.session == nil)
      #expect(model.user == nil)

      storage.isLocked.setValue(false)
      await client.initialization()
      try #require(await waitUntil { await !model.isLoading })

      #expect(model.status == .signedOut(.sessionMissing))
      #expect(model.session == nil)
    }

    @Test
    func startsWithTheStatusTheClientAlreadyHolds() async throws {
      guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }

      try await sut.seedSession(.valid)

      let model = AuthModel(client: sut)

      #expect(model.status == .signedIn(.valid))
      #expect(!model.isLoading)
      #expect(model.session == .valid)
      #expect(model.user == Session.valid.user)
    }

    @Test
    func mirrorsEveryChange() async throws {
      guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }

      let model = AuthModel(client: sut)
      try #require(await waitUntil { await !model.isLoading })
      let refreshed = {
        var session = Session.valid; session.accessToken = "refreshed"; return session
      }()
      let updated = {
        var session = refreshed; session.user.email = "updated@example.com"; return session
      }()

      try await store.commit(.signedIn(.valid, event: .signedIn))
      try #require(await waitUntil { await model.status == .signedIn(.valid) })

      try await store.commit(.signedIn(refreshed, event: .tokenRefreshed))
      try #require(await waitUntil { await model.status == .signedIn(refreshed) })

      try await store.commit(.userChangeVerified(updated))
      try #require(await waitUntil { await model.status == .signedIn(updated) })

      try await store.commit(.signedOut(.userInitiated, event: .signedOut))
      try #require(await waitUntil { await model.status == .signedOut(.userInitiated) })
      #expect(model.session == nil)
      #expect(model.user == nil)
    }

    @Test
    func notifiesObserversOfAChange() async throws {
      guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }

      let model = AuthModel(client: sut)
      try #require(await waitUntil { await !model.isLoading })

      let (changed, notify) = AsyncStream<Void>.makeStream()
      withObservationTracking {
        _ = model.session
      } onChange: {
        notify.yield()
      }
      try await store.commit(.signedIn(.valid, event: .signedIn))

      try await withTimeout(.seconds(5)) {
        for await _ in changed { break }
      }

      #expect(model.session == .valid)
    }

    @Test
    func deinitCancelsTheSubscription() async throws {
      guard #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) else { return }

      let store = store
      let before = store.subscriberCount
      var model: AuthModel? = AuthModel(client: sut)
      withExtendedLifetime(model) { #expect(store.subscriberCount == before + 1) }

      model = nil

      try #require(await waitUntil { store.subscriberCount == before })
    }
  }
#endif
