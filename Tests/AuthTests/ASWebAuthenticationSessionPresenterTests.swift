//
//  ASWebAuthenticationSessionPresenterTests.swift
//  Auth
//
//  Created by Guilherme Souza on 04/11/26.
//

import Foundation
import Testing

@testable import Auth

#if canImport(AuthenticationServices)
  import AuthenticationServices

  @MainActor
  final class FakeWebAuthSession: WebAuthSession {
    let url: URL
    let callback: WebAuthCallback
    let prefersEphemeralWebBrowserSession: Bool
    private let completion: @Sendable (URL?, (any Error)?) -> Void
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    init(
      url: URL,
      callback: WebAuthCallback,
      prefersEphemeralWebBrowserSession: Bool,
      completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) {
      self.url = url
      self.callback = callback
      self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
      self.completion = completion
    }

    func start() {
      startCount += 1
    }

    /// Like the system session: cancelling reports `canceledLogin` to the completion handler.
    func cancel() {
      cancelCount += 1
      completion(nil, ASWebAuthenticationSessionError(.canceledLogin))
    }

    func complete(with url: URL) {
      completion(url, nil)
    }

    func fail(with error: any Error) {
      completion(nil, error)
    }
  }

  @MainActor
  final class FakeWebAuthSessions {
    private(set) var created: [FakeWebAuthSession] = []

    func make(
      url: URL,
      callback: WebAuthCallback,
      prefersEphemeralWebBrowserSession: Bool,
      completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) -> any WebAuthSession {
      let session = FakeWebAuthSession(
        url: url,
        callback: callback,
        prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
        completion: completion
      )
      created.append(session)
      return session
    }

    /// Suspends until the presenter has started the `count`th session.
    func started(_ count: Int = 1) async -> FakeWebAuthSession {
      while created.count < count || created[count - 1].startCount == 0 {
        await Task.yield()
      }
      return created[count - 1]
    }
  }

  @Suite
  struct ASWebAuthenticationSessionPresenterTests {
    static let authorizeURL = URL(string: "https://example.supabase.co/auth/v1/authorize")!
    static let callbackURL = URL(string: "myapp://callback?code=abc")!

    @MainActor
    private func makePresenter(
      _ sessions: FakeWebAuthSessions,
      prefersEphemeralWebBrowserSession: Bool = false,
      httpsCallbacksAvailable: Bool = true,
      activeSession: ActiveWebAuthSession = ActiveWebAuthSession()
    ) -> ASWebAuthenticationSessionPresenter {
      ASWebAuthenticationSessionPresenter(
        prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
        httpsCallbacksAvailable: httpsCallbacksAvailable,
        activeSession: activeSession,
        makeSession: {
          sessions.make(
            url: $0, callback: $1, prefersEphemeralWebBrowserSession: $2, completion: $3)
        }
      )
    }

    // MARK: Cancellation

    @Test
    @MainActor
    func cancellingTheAwaitingTaskCancelsTheSession() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "myapp://callback"))
      }
      let session = await sessions.started()
      #expect(session.cancelCount == 0)

      task.cancel()

      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(session.cancelCount == 1)
    }

    @Test
    @MainActor
    func aTaskCancelledBeforeItStartsStillCancelsTheSession() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "myapp://callback"))
      }
      task.cancel()

      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(sessions.created.map(\.cancelCount) == [1])
    }

    @Test
    @MainActor
    func aCancelledLoginThrowsCancellationError() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "myapp://callback"))
      }
      let session = await sessions.started()
      session.fail(with: ASWebAuthenticationSessionError(.canceledLogin))

      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(session.cancelCount == 0)
    }

    // MARK: Result

    @Test
    @MainActor
    func returnsTheCallbackURL() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "myapp://callback"))
      }
      let session = await sessions.started()
      #expect(session.url == Self.authorizeURL)
      session.complete(with: Self.callbackURL)

      #expect(try await task.value == Self.callbackURL)
    }

    @Test
    @MainActor
    func passesTheEphemeralPreferenceToTheSession() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions, prefersEphemeralWebBrowserSession: true)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "myapp://callback"))
      }
      let session = await sessions.started()
      session.complete(with: Self.callbackURL)
      _ = try await task.value

      #expect(session.prefersEphemeralWebBrowserSession)
    }

    @Test
    @MainActor
    func aNilRedirectURLThrowsTheGuidanceWithoutStartingASession() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let error = await #expect(throws: AuthError.self) {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: nil)
      }

      #expect(error?.kind == .oauthFlowFailed)
      #expect(error?.message.contains("redirectTo") == true)
      #expect(sessions.created.isEmpty)
    }

    // MARK: Callback

    @Test
    func anHTTPSRedirectUsesAnHTTPSCallbackWhereAvailable() {
      let callback = ASWebAuthenticationSessionPresenter.callback(
        for: URL(string: "https://example.com/auth/callback?x=1")!,
        httpsCallbacksAvailable: true
      )

      #expect(callback == .https(host: "example.com", path: "/auth/callback"))
    }

    @Test
    func anHTTPSRedirectFallsBackToTheSchemeWhereUnavailable() {
      let callback = ASWebAuthenticationSessionPresenter.callback(
        for: URL(string: "https://example.com/auth/callback")!,
        httpsCallbacksAvailable: false
      )

      #expect(callback == .scheme("https"))
    }

    @Test(arguments: [true, false])
    func aCustomSchemeRedirectAlwaysUsesTheScheme(httpsCallbacksAvailable: Bool) {
      let callback = ASWebAuthenticationSessionPresenter.callback(
        for: URL(string: "myapp://callback")!,
        httpsCallbacksAvailable: httpsCallbacksAvailable
      )

      #expect(callback == .scheme("myapp"))
    }

    @Test
    func aRedirectWithoutASchemeHasNoCallback() {
      #expect(
        ASWebAuthenticationSessionPresenter.callback(
          for: URL(string: "/callback")!, httpsCallbacksAvailable: true) == nil)
    }

    @Test
    @MainActor
    func theSessionGetsTheChosenCallback() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions, httpsCallbacksAvailable: true)

      let task = Task {
        try await presenter.authenticate(
          url: Self.authorizeURL, redirectURL: URL(string: "https://example.com/callback"))
      }
      let session = await sessions.started()
      session.complete(with: Self.callbackURL)
      _ = try await task.value

      #expect(session.callback == .https(host: "example.com", path: "/callback"))
    }

    @Test
    @MainActor
    func theSchemeOnlyRequirementUsesTheSchemeCallback() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)

      let task = Task {
        try await presenter.authenticate(url: Self.authorizeURL, callbackScheme: "myapp")
      }
      let session = await sessions.started()
      session.complete(with: Self.callbackURL)
      _ = try await task.value

      #expect(session.callback == .scheme("myapp"))
    }

    // MARK: One active session

    @Test
    @MainActor
    func aSecondSessionWhileOneIsOpenThrows() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)
      let redirectURL = URL(string: "myapp://callback")

      let first = Task {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: redirectURL)
      }
      let session = await sessions.started()

      let error = await #expect(throws: AuthError.self) {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: redirectURL)
      }
      #expect(error?.kind == .oauthFlowFailed)
      #expect(sessions.created.count == 1)

      session.complete(with: Self.callbackURL)
      #expect(try await first.value == Self.callbackURL)
    }

    @Test
    @MainActor
    func aNewSessionCanStartOnceTheLastOneFinished() async throws {
      let sessions = FakeWebAuthSessions()
      let presenter = makePresenter(sessions)
      let redirectURL = URL(string: "myapp://callback")

      let first = Task {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: redirectURL)
      }
      await sessions.started().fail(with: ASWebAuthenticationSessionError(.canceledLogin))
      await #expect(throws: CancellationError.self) { try await first.value }

      let second = Task {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: redirectURL)
      }
      await sessions.started(2).complete(with: Self.callbackURL)

      #expect(try await second.value == Self.callbackURL)
    }

    // MARK: Protocol default

    @Test
    @MainActor
    func theDefaultRedirectURLRequirementForwardsTheScheme() async throws {
      struct SchemeRecorder: WebAuthPresenter {
        let received: @MainActor @Sendable (String?) -> Void

        func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
          received(callbackScheme)
          return url
        }
      }

      final class Received: @unchecked Sendable { var schemes: [String?] = [] }
      let received = Received()
      let presenter = SchemeRecorder { received.schemes.append($0) }

      _ = try await presenter.authenticate(
        url: Self.authorizeURL, redirectURL: URL(string: "https://example.com/callback"))
      _ = try await presenter.authenticate(url: Self.authorizeURL, redirectURL: nil)

      #expect(received.schemes == ["https", nil])
    }
  }
#endif
