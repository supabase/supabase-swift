import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthMockerTests {
  @Suite(.mockerSerialized, .mainSerialExecutorSerialized)
  struct AuthEventsV3APITests {
    init() {
      Mocker.removeAll()
    }

    @Test
    func statusFollowsTheStoredSession() {
      let client = V3TestClient()
      #expect(client.sut.status == .signedOut(nil))

      client.storeSession()
      #expect(client.sut.status == .signedIn(.validSession))
    }

    @Test
    func eventsStartWithTheInitialSession() async {
      let client = V3TestClient()
      client.storeSession()

      var iterator = client.sut.events().makeAsyncIterator()
      let change = await iterator.next()

      #expect(change?.event == .initialSession)
      #expect(change?.status == .signedIn(.validSession))
      #expect(change?.session == .validSession)
      #expect(change?.signOutReason == nil)
    }

    @Test
    func eventsStartSignedOutWithNoSession() async {
      let client = V3TestClient()

      var iterator = client.sut.events().makeAsyncIterator()
      let change = await iterator.next()

      #expect(change == AuthChange(event: .initialSession, status: .signedOut(nil)))
      #expect(change?.session == nil)
    }

    @Test
    func eventsDeliverSignOut() async throws {
      mock("logout", status: 204)
      let client = V3TestClient()
      client.storeSession()

      var iterator = client.sut.events().makeAsyncIterator()
      _ = await iterator.next()
      try await client.sut.signOut()
      let change = await iterator.next()

      #expect(change?.event == .signedOut)
      #expect(change?.status == .signedOut(nil))
      #expect(change?.session == nil)
      #expect(client.sut.status == .signedOut(nil))
    }

    @Test
    func eventsKeepAStoredSessionWhenTheFirstRefreshFails() async {
      Mock(
        url: clientURL.appendingPathComponent("token"), ignoreQuery: true, statusCode: 500,
        data: [.post: Data()], requestError: URLError(.notConnectedToInternet)
      ).register()
      let client = V3TestClient()
      client.storeSession(.expiredSession)

      var iterator = client.sut.events().makeAsyncIterator()
      let change = await iterator.next()

      #expect(change?.event == .initialSession)
      #expect(change?.status == .signedIn(.expiredSession))
      #expect(change?.status == client.sut.status)
    }

    @Test
    func eventsRemoveTheListenerWhenTheStreamEnds() async {
      let client = V3TestClient()
      let emitter = Dependencies[client.sut.clientID].eventEmitter.emitter

      let stream = client.sut.events()
      #expect(emitter.listenerCount == 1)

      let task = Task { for await _ in stream {} }
      task.cancel()
      await Task.megaYield()

      #expect(emitter.listenerCount == 0)
    }

    @available(*, deprecated, message: "Compares with the deprecated v2 stream.")
    @Test
    func eventsMatchTheDeprecatedStream() async {
      let client = V3TestClient()
      client.storeSession()

      var old = client.sut.authStateChanges.makeAsyncIterator()
      var new = client.sut.events().makeAsyncIterator()
      let oldChange = await old.next()
      let newChange = await new.next()

      #expect(oldChange?.event == newChange?.event)
      #expect(oldChange?.session == newChange?.session)
    }

    @available(*, deprecated, message: "Covers the deprecated v2 listener.")
    @Test
    func deprecatedListenerAndNotificationStillWork() async {
      let client = V3TestClient()
      client.storeSession()
      let events = LockIsolated<[AuthChangeEvent]>([])
      let posted = LockIsolated<[AuthChangeEvent]>([])

      let observer = NotificationCenter.default.addObserver(
        forName: AuthClient.didChangeAuthStateNotification, object: nil, queue: nil
      ) { notification in
        guard
          let event = notification.userInfo?[AuthClient.authChangeEventInfoKey] as? AuthChangeEvent,
          notification.userInfo?[AuthClient.authChangeSessionInfoKey] is Session
        else { return }
        posted.withValue { $0.append(event) }
      }
      defer { NotificationCenter.default.removeObserver(observer) }

      let listener: AuthStateChangeListener = { event, _ in events.withValue { $0.append(event) } }
      let registration: any AuthStateChangeListenerRegistration =
        await client.sut.onAuthStateChange(listener)
      registration.remove()

      #expect(events.value == [.initialSession])
      #expect(posted.value.contains(.initialSession))
    }

    @Test
    func authChangeValues() {
      let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
      #expect(signedOut.signOutReason == .userInitiated)
      #expect(signedOut.session == nil)

      let initial = AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))
      #expect(initial.signOutReason == nil)

      let signedIn = AuthChange(event: .signedIn, status: .signedIn(.validSession))
      #expect(signedIn.session == .validSession)
      #expect(signedIn.description.contains("SIGNED_IN"))
      #expect(!signedIn.description.contains(Session.validSession.accessToken))
      #expect(!signedIn.description.contains(Session.validSession.refreshToken))

      #expect(AuthStatus.loading != .signedOut(nil))
    }

    @Test
    func signOutReason() {
      let reason: SignOutReason = "sessionExpired"
      #expect(reason == .sessionExpired)
      #expect(SignOutReason(rawValue: "sessionRevoked") == .sessionRevoked)
      #expect(SignOutReason.userInitiated.rawValue == "userInitiated")
      #expect(SignOutReason.sessionMissing.rawValue == "sessionMissing")
    }

    #if canImport(Observation)
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
      @MainActor
      @Test
      func authModelFollowsTheClient() async throws {
        mock("logout", status: 204)
        let client = V3TestClient()
        client.storeSession()

        let model = AuthModel(client: client.sut)
        #expect(model.status == .signedIn(.validSession))
        #expect(model.session == .validSession)
        #expect(model.user == Session.validSession.user)
        #expect(!model.isLoading)

        try await client.sut.signOut()
        for _ in 0..<200 where model.session != nil {
          try await Task.sleep(nanoseconds: 5_000_000)
        }

        #expect(model.status == .signedOut(nil))
        #expect(model.user == nil)
      }
    #endif
  }
}
