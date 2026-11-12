//
//  WebAuthenticationSessionPresenterTests.swift
//  Auth
//
//  Created by Guilherme Souza on 12/11/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import Auth

#if canImport(_AuthenticationServices_SwiftUI)
  import AuthenticationServices
  import SwiftUI
  import _AuthenticationServices_SwiftUI

  /// Records each call that the presenter makes to the SwiftUI session. The real session needs a
  /// window and a user, so the tests replace it.
  @MainActor
  final class SessionCalls {
    struct Call: Equatable {
      let url: URL
      let callback: WebAuthCallback
      let prefersEphemeralWebBrowserSession: Bool
    }

    private(set) var calls: [Call] = []
    var result: Result<URL, any Error>

    init(result: Result<URL, any Error>) {
      self.result = result
    }

    func authenticate(
      url: URL, callback: WebAuthCallback, prefersEphemeralWebBrowserSession: Bool
    ) throws -> URL {
      calls.append(
        Call(
          url: url, callback: callback,
          prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession))
      return try result.get()
    }
  }

  @Suite(.timeLimit(.minutes(1)))
  @MainActor
  struct WebAuthenticationSessionPresenterTests {
    static let authorizeURL = URL(string: "https://example.supabase.co/auth/v1/authorize")!
    static let redirectURL = URL(string: "myapp://callback")
    static let callbackURL = URL(string: "myapp://callback?code=abc")!

    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    private func makePresenter(
      _ calls: SessionCalls,
      prefersEphemeralWebBrowserSession: Bool = false,
      httpsCallbacksAvailable: Bool = true,
      activeSession: ActiveWebAuthSession = ActiveWebAuthSession()
    ) -> WebAuthenticationSessionPresenter {
      WebAuthenticationSessionPresenter(
        prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
        httpsCallbacksAvailable: httpsCallbacksAvailable,
        activeSession: activeSession,
        openPage: { url, callback, ephemeral in
          try calls.authenticate(
            url: url, callback: callback, prefersEphemeralWebBrowserSession: ephemeral)
        }
      )
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aCustomSchemeRedirectListensForTheScheme() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      let url = try await makePresenter(calls).authenticate(
        url: Self.authorizeURL, redirectURL: Self.redirectURL)

      #expect(url == Self.callbackURL)
      #expect(
        calls.calls == [
          .init(
            url: Self.authorizeURL, callback: .scheme("myapp"),
            prefersEphemeralWebBrowserSession: false)
        ])
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func anHTTPSRedirectListensForTheUniversalLink() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      _ = try await makePresenter(calls, httpsCallbacksAvailable: true).authenticate(
        url: Self.authorizeURL, redirectURL: URL(string: "https://example.com/auth/callback"))

      #expect(calls.calls.map(\.callback) == [.https(host: "example.com", path: "/auth/callback")])
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func anHTTPSRedirectFallsBackToTheSchemeWhereUnavailable() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      _ = try await makePresenter(calls, httpsCallbacksAvailable: false).authenticate(
        url: Self.authorizeURL, redirectURL: URL(string: "https://example.com/auth/callback"))

      #expect(calls.calls.map(\.callback) == [.scheme("https")])
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func theCallbackSchemeEntryPointListensForTheScheme() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      _ = try await makePresenter(calls).authenticate(
        url: Self.authorizeURL, callbackScheme: "myapp")

      #expect(calls.calls.map(\.callback) == [.scheme("myapp")])
    }

    @Test(arguments: [true, false])
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func theEphemeralPreferenceReachesTheSession(prefersEphemeral: Bool) async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      _ = try await makePresenter(calls, prefersEphemeralWebBrowserSession: prefersEphemeral)
        .authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)

      #expect(calls.calls.map(\.prefersEphemeralWebBrowserSession) == [prefersEphemeral])
    }

    @Test(arguments: [nil, URL(string: "/callback")])
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aRedirectWithoutASchemeThrowsAndOpensNoPage(redirectURL: URL?) async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      let error = await #expect(throws: AuthError.self) {
        try await makePresenter(calls).authenticate(
          url: Self.authorizeURL, redirectURL: redirectURL)
      }
      #expect(error?.kind == .oauthFlowFailed)
      #expect(calls.calls.isEmpty)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aNilCallbackSchemeThrowsAndOpensNoPage() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))

      let error = await #expect(throws: AuthError.self) {
        try await makePresenter(calls).authenticate(url: Self.authorizeURL, callbackScheme: nil)
      }
      #expect(error?.kind == .oauthFlowFailed)
      #expect(calls.calls.isEmpty)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aSecondPageWhileOneIsOpenThrows() async throws {
      let activeSession = ActiveWebAuthSession()
      let opened = AsyncStream<Void>.makeStream()
      let finish = AsyncStream<URL>.makeStream()
      let first = WebAuthenticationSessionPresenter(
        prefersEphemeralWebBrowserSession: false,
        httpsCallbacksAvailable: true,
        activeSession: activeSession,
        openPage: { _, _, _ in
          opened.continuation.yield()
          for await url in finish.stream { return url }
          throw CancellationError()
        }
      )
      let calls = SessionCalls(result: .success(Self.callbackURL))
      let second = makePresenter(calls, activeSession: activeSession)

      let firstTask = Task {
        try await first.authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
      for await _ in opened.stream { break }

      let error = await #expect(throws: AuthError.self) {
        try await second.authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
      #expect(error?.kind == .oauthFlowFailed)
      #expect(calls.calls.isEmpty)

      finish.continuation.yield(Self.callbackURL)
      #expect(try await firstTask.value == Self.callbackURL)
      #expect(
        try await second.authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)
          == Self.callbackURL)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aFailedPageFreesTheSlot() async throws {
      let activeSession = ActiveWebAuthSession()
      let calls = SessionCalls(result: .failure(ASWebAuthenticationSessionError(.canceledLogin)))
      let presenter = makePresenter(calls, activeSession: activeSession)

      await #expect(throws: CancellationError.self) {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
      #expect(activeSession.begin() != nil)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func closingThePageThrowsCancellationError() async throws {
      let calls = SessionCalls(result: .failure(ASWebAuthenticationSessionError(.canceledLogin)))

      await #expect(throws: CancellationError.self) {
        try await makePresenter(calls).authenticate(
          url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func anotherSessionErrorPassesThrough() async throws {
      let calls = SessionCalls(
        result: .failure(ASWebAuthenticationSessionError(.presentationContextInvalid)))

      let error = await #expect(throws: ASWebAuthenticationSessionError.self) {
        try await makePresenter(calls).authenticate(
          url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
      #expect(error?.code == .presentationContextInvalid)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func aTaskCancelledBeforeItStartsOpensNoPage() async throws {
      let calls = SessionCalls(result: .success(Self.callbackURL))
      let presenter = makePresenter(calls)

      let task = Task {
        try await presenter.authenticate(url: Self.authorizeURL, redirectURL: Self.redirectURL)
      }
      task.cancel()

      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(calls.calls.isEmpty)
    }

    @Test
    @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
    func theFactoryWrapsTheEnvironmentSession() {
      let session = EnvironmentValues().webAuthenticationSession

      let presenter: WebAuthenticationSessionPresenter = .webAuthenticationSession(
        session, prefersEphemeralWebBrowserSession: true)

      #expect(presenter.prefersEphemeralWebBrowserSession)
      #expect(!WebAuthenticationSessionPresenter(session).prefersEphemeralWebBrowserSession)
    }
  }
#endif
