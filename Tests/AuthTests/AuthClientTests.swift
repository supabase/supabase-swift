//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Helpers
import InlineSnapshotTesting
import Mocker
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

private let apiKey =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

extension AuthMockerTests {
  @Suite(.mockerSerialized, .mainSerialExecutorSerialized)
  struct AuthClientTests {
    let storage = InMemoryLocalStorage()

    init() {
      Mocker.removeAll()
    }

    @Test
    func eventsStartWithInitialSession() async throws {
      try await withMainSerialExecutor {
        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let change = await sut.events().first { _ in true }

        expectNoDifference(change, AuthChange(event: .initialSession, status: .signedIn(.valid)))
        expectNoDifference(sut.status, .signedIn(.valid))
      }
    }

    @Test
    func eventsKeepAChangeAppliedBeforeTheFirstRead() async throws {
      try await withMainSerialExecutor {
        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let events = sut.events()
        try await sut.dependencies.sessionStore.commit(
          .signedOut(.userInitiated, event: .signedOut))
        let changes = await events.prefix(2).collect()

        expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
        expectNoDifference(changes.last?.signOutReason, .userInitiated)
        expectNoDifference(sut.status, .signedOut(.userInitiated))
      }
    }

    @Test
    func eventsFinishWhenTheClientIsReleased() async throws {
      var sut: AuthClient? = makeSUT()
      let events = try #require(sut).events()

      sut = nil
      let changes = try await withTimeout(.seconds(5)) { await events.collect() }

      expectNoDifference(
        changes, [AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))])
    }

    @Test
    func eventsReleaseTheSubscriberWhenCancelledBeforeTheFirstRead() async throws {
      await withMainSerialExecutor {
        let sut = makeSUT()
        let store = sut.dependencies.sessionStore
        let subscribersBefore = store.subscriberCount

        let stream = sut.events()

        expectNoDifference(store.subscriberCount, subscribersBefore + 1)

        let consumer = Task {
          for await _ in stream {}
        }
        consumer.cancel()

        await Task.megaYield()

        expectNoDifference(store.subscriberCount, subscribersBefore)
      }
    }

    @Test
    func globalSignOutKeepsASessionSignedInWhileLoggingOut() async throws {
      try await withMainSerialExecutor {
        let sut = makeSUT()

        var nextSession = Session.valid
        nextSession.accessToken = "next-access-token"
        nextSession.refreshToken = "next-refresh-token"

        var mock = Mock(
          url: clientURL.appendingPathComponent("logout"),
          ignoreQuery: true,
          statusCode: 204,
          data: [.post: Data()]
        )
        mock.onRequestHandler = OnRequestHandler(requestCallback: { [nextSession] _ in
          let signedIn = DispatchSemaphore(value: 0)
          Task {
            try? await sut.seedSession(nextSession)
            signedIn.signal()
          }
          _ = signedIn.wait(timeout: .now() + 5)
        })
        mock.register()

        try await sut.seedSession(.valid)

        try await sut.signOut(scope: .global)

        expectNoDifference(sut.currentSession, nextSession)
      }
    }

    @Test
    func signInAnonymously() async throws {
      try await withMainSerialExecutor {
        let session = Session(fromMockNamed: "anonymous-sign-in-response")

        Mock(
          url: clientURL.appendingPathComponent("signup"),
          statusCode: 200,
          data: [
            .post: MockData.anonymousSignInResponse
          ]
        )
        .snapshotRequest {
          #"""
          curl \
          	--request POST \
          	--header "Content-Length: 2" \
          	--header "Content-Type: application/json" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
          	--data "{}" \
          	"http://localhost:54321/auth/v1/signup"
          """#
        }
        .register()

        let sut = makeSUT()

        try await assertAuthStateChanges(
          sut: sut,
          action: { try await sut.signInAnonymously() },
          expectedEvents: [.initialSession, .signedIn],
          expectedSessions: [nil, session]
        )

        expectNoDifference(sut.currentSession, session)
        expectNoDifference(sut.currentUser, session.user)
      }
    }

    @Test
    func oauthSignInThroughHandleRedirect() async throws {
      try await withMainSerialExecutor {
        Mock(
          url: clientURL.appendingPathComponent("token").appendingQueryItems([
            URLQueryItem(name: "grant_type", value: "pkce")
          ]),
          statusCode: 200,
          data: [
            .post: MockData.session
          ]
        )
        .snapshotRequest {
          #"""
          curl \
          	--request POST \
          	--header "Content-Length: 126" \
          	--header "Content-Type: application/json" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
          	--data "{\"auth_code\":\"12345\",\"code_verifier\":\"nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA\"}" \
          	"http://localhost:54321/auth/v1/token?grant_type=pkce"
          """#
        }
        .register()

        let sut = makeSUT()

        let eventsTask = Task {
          await sut.events().prefix(2).collect()
        }

        await Task.megaYield()

        _ = try await sut.oauthSignInURL(
          .google, options: OAuthOptions(redirectTo: URL(string: "supabase://auth-callback")))
        try await sut.handleRedirect(URL(string: "supabase://auth-callback?code=12345")!)

        let events = await eventsTask.value.map(\.event)

        expectNoDifference(events, [.initialSession, .signedIn])
      }
    }

    @Test
    func concurrentPKCEFlowsKeepIndependentVerifiers() async throws {
      try await withMainSerialExecutor {
        let sut = makeSUT()
        try await sut.seedSession(.valid)

        Mock(
          url: clientURL.appendingPathComponent("user/identities/authorize"),
          ignoreQuery: true,
          statusCode: 200,
          data: [
            .get: Data(#"{"url": "https://github.com/login/oauth/authorize"}"#.utf8)
          ]
        )
        .register()

        let flowA = try await sut.linkIdentityURL(.github).id

        let flowB = try await sut.linkIdentityURL(.google).id

        #expect(flowA != flowB)

        Mock(
          url: clientURL.appendingPathComponent("token").appendingQueryItems([
            URLQueryItem(name: "grant_type", value: "pkce")
          ]),
          statusCode: 200,
          data: [
            .post: MockData.session
          ]
        )
        .register()

        _ = try await sut.exchangeCodeForSession("code-a", flowID: flowA)

        #expect(try await sut.dependencies.flowStore.flow(id: flowA) == nil)
        #expect(try await sut.dependencies.flowStore.flow(id: flowB) != nil)
      }
    }

    @Test
    func linkIdentityURL() async throws {
      try await withMainSerialExecutor {
        let url =
          "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
        let sut = makeSUT()

        Mock(
          url: clientURL.appendingPathComponent("user/identities/authorize"),
          ignoreQuery: true,
          statusCode: 200,
          data: [
            .get: Data(
              """
              {
                "url": "\(url)"
              }
              """.utf8
            )
          ]
        )
        .snapshotRequest {
          #"""
          curl \
          	--header "Authorization: Bearer accesstoken" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
          	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true"
          """#
        }
        .register()

        try await sut.seedSession(.valid)

        let flow = try await sut.linkIdentityURL(.github)

        expectNoDifference(flow.url, URL(string: url)!)
        #expect(try await sut.dependencies.flowStore.flow(id: flow.id) != nil)
      }
    }

    @Test
    func linkIdentityIDTokenEmitsUserUpdated() async throws {
      try await withMainSerialExecutor {
        Mock(
          url: clientURL.appendingPathComponent("token"),
          ignoreQuery: true,
          statusCode: 200,
          data: [.post: MockData.session]
        )
        .snapshotRequest {
          #"""
          curl \
          	--request POST \
          	--header "Authorization: Bearer accesstoken" \
          	--header "Content-Length: 166" \
          	--header "Content-Type: application/json" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
          	--data "{\"access_token\":\"access-token\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"id_token\":\"id-token\",\"link_identity\":true,\"nonce\":\"nonce\",\"provider\":\"apple\"}" \
          	"http://localhost:54321/auth/v1/token?grant_type=id_token"
          """#
        }
        .register()

        let sut = makeSUT()

        try await sut.seedSession(.valid)

        let updatedSession = try await assertAuthStateChanges(
          sut: sut,
          action: {
            try await sut.linkIdentity(
              idToken: IDTokenCredentials(
                provider: .apple,
                idToken: "id-token",
                nonce: "nonce",
                accessToken: "access-token",
                captchaToken: "captcha-token"
              )
            )
          },
          expectedEvents: [.initialSession, .userUpdated]
        )

        expectNoDifference(sut.currentSession, updatedSession)
      }
    }

    @Test
    func adminListUsers() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: MockData.listUsersResponse
        ],
        additionalHeaders: [
          "X-Total-Count": "669",
          "Link":
            "</admin/users?page=2&per_page=>; rel=\"next\", </admin/users?page=14&per_page=>; rel=\"last\"",
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/admin/users"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      let response = try await sut.listUsers()
      expectNoDifference(response.total, 669)
      expectNoDifference(response.nextPage, 2)
      expectNoDifference(response.lastPage, 14)
    }

    @Test
    func adminListUsers_noNextPage() async throws {
      Mock(
        url: clientURL.appendingPathComponent("admin/users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .get: MockData.listUsersResponse
        ],
        additionalHeaders: [
          "X-Total-Count": "669",
          "Link": "</admin/users?page=14&per_page=>; rel=\"last\"",
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/admin/users"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      let response = try await sut.listUsers()
      expectNoDifference(response.total, 669)
      #expect(response.nextPage == nil)
      expectNoDifference(response.lastPage, 14)
    }

    @Test
    func signUpWithEmailAndPassword() async throws {
      Mock(
        url: clientURL.appendingPathComponent("signup"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 238" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\"}" \
        	"http://localhost:54321/auth/v1/signup?redirect_to=https://supabase.com"
        """#
      }
      .register()

      let sut = makeSUT()

      _ = try await sut.signUp(
        email: "example@mail.com",
        password: "the.pass",
        options: SignUpOptions(
          userMetadata: ["custom_key": .string("custom_value")],
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "dummy-captcha"
        )
      )
    }

    @Test
    func signUpWithPhoneAndPassword() async throws {
      Mock(
        url: clientURL.appendingPathComponent("signup"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 159" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"channel\":\"sms\",\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\",\"phone\":\"+1 202-918-2132\"}" \
        	"http://localhost:54321/auth/v1/signup"
        """#
      }
      .register()

      let sut = makeSUT()

      _ = try await sut.signUp(
        phone: "+1 202-918-2132",
        password: "the.pass",
        options: SignUpOptions(
          userMetadata: ["custom_key": .string("custom_value")],
          captchaToken: "dummy-captcha"
        )
      )
    }

    @Test
    func signUpWhenConfirmationRequired() async throws {
      Mock(
        url: clientURL.appendingPathComponent("signup"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.signUpConfirmationRequired]
      ).register()

      let sut = makeSUT()

      let result = try await sut.signUp(
        email: "jane@example.com",
        password: "the.pass"
      )

      guard case .confirmationRequired(let user) = result else {
        Issue.record("Expected .confirmationRequired, got \(result)")
        return
      }
      #expect(user.email == "jane@example.com")
      #expect(sut.currentSession == nil)
    }

    @Test
    func signUpWhenSignedInCommitsTheSession() async throws {
      Mock(
        url: clientURL.appendingPathComponent("signup"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()

      let sut = makeSUT()

      let result = try await sut.signUp(email: "jane@example.com", password: "the.pass")

      guard case .signedIn(let session) = result else {
        Issue.record("Expected .signedIn, got \(result)")
        return
      }
      expectNoDifference(sut.currentSession, session)
    }

    @Test
    func signInWithEmailAndPassword() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 107" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=password"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signIn(
        email: "example@mail.com",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }

    @Test
    func signInWithPhoneAndPassword() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 106" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\",\"phone\":\"+1 202-918-2132\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=password"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signIn(
        phone: "+1 202-918-2132",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }

    @Test
    func signInWithIdToken() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 167" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"access_token\":\"access-token\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"id_token\":\"id-token\",\"link_identity\":false,\"nonce\":\"nonce\",\"provider\":\"apple\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=id_token"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signInWithIDToken(
        IDTokenCredentials(
          provider: .apple,
          idToken: "id-token",
          nonce: "nonce",
          accessToken: "access-token",
          captchaToken: "captcha-token"
        )
      )
    }

    @Test
    func signInWithWeb3Ethereum() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 448" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"chain\":\"ethereum\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"message\":\"example.com wants you to sign in with your Ethereum account:\n0x2c7536E3605D9C16a7a3D7b1898e529396a65c23\n\nURI: https:\/\/example.com\nVersion: 1\nChain ID: 1\nNonce: abc123\nIssued At: 2026-01-01T00:00:00.000Z\",\"signature\":\"0x468cc42ece552183597cbbbd0418a5d3efff707a1021a222ad16e55124327ee670d363a8ee08976b5bd5f7af5e3ac53a4e43983a9ac7f4853a75423fcc387ddc1c\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=web3"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signInWithWeb3(
        Web3Credentials(
          chain: .ethereum,
          message:
            "example.com wants you to sign in with your Ethereum account:\n0x2c7536E3605D9C16a7a3D7b1898e529396a65c23\n\nURI: https://example.com\nVersion: 1\nChain ID: 1\nNonce: abc123\nIssued At: 2026-01-01T00:00:00.000Z",
          signature:
            "0x468cc42ece552183597cbbbd0418a5d3efff707a1021a222ad16e55124327ee670d363a8ee08976b5bd5f7af5e3ac53a4e43983a9ac7f4853a75423fcc387ddc1c",
          captchaToken: "captcha-token"
        )
      )
    }

    @Test
    func signInWithWeb3Solana() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 305" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"chain\":\"solana\",\"message\":\"example.com wants you to sign in with your Solana account:\n4Cw1koUQtqybLFem7uqhzMBznMPGARbFS4cjaYbM9RnR\n\nURI: https:\/\/example.com\nVersion: 1\nIssued At: 2026-01-01T00:00:00.000Z\",\"signature\":\"dGVzdC1zaWduYXR1cmUtYnl0ZXMtdGhhdC1hcmUtNjQtYnl0ZXMtbG9uZy1mb3ItdGVzdGluZw==\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=web3"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signInWithWeb3(
        Web3Credentials(
          chain: .solana,
          message:
            "example.com wants you to sign in with your Solana account:\n4Cw1koUQtqybLFem7uqhzMBznMPGARbFS4cjaYbM9RnR\n\nURI: https://example.com\nVersion: 1\nIssued At: 2026-01-01T00:00:00.000Z",
          signature: "dGVzdC1zaWduYXR1cmUtYnl0ZXMtdGhhdC1hcmUtNjQtYnl0ZXMtbG9uZy1mb3ItdGVzdGluZw=="
        )
      )
    }

    @Test
    func signInWithWeb3UnsupportedChainError() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 400,
        data: [
          .post: Data(
            """
            {
              "error_code": "web3_unsupported_chain",
              "msg": "Unsupported chain"
            }
            """.utf8
          )
        ]
      )
      .register()

      let sut = makeSUT()

      do {
        _ = try await sut.signInWithWeb3(
          Web3Credentials(
            chain: "bitcoin",
            message: "irrelevant",
            signature: "irrelevant"
          )
        )
        Issue.record("Expected AuthError.server")
      } catch let error as AuthError {
        #expect(error.kind == .server)
        #expect(error.errorCode == .web3UnsupportedChain)
        #expect(error.response?.statusCode == 400)
      }
    }

    @Test
    func signInWithOTPUsingEmail() async throws {
      Mock(
        url: clientURL.appendingPathComponent("otp"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 235" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"}}" \
        	"http://localhost:54321/auth/v1/otp?redirect_to=https://supabase.com"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.signInWithOTP(
        email: "example@mail.com",
        options: EmailOTPOptions(
          shouldCreateUser: true,
          userMetadata: ["custom_key": .string("custom_value")],
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "dummy-captcha"
        )
      )
    }

    @Test
    func signInWithOTPUsingPhone() async throws {
      Mock(
        url: clientURL.appendingPathComponent("otp"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"message_id":"SM123"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 161" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"channel\":\"whatsapp\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"phone\":\"+1 202-918-2132\"}" \
        	"http://localhost:54321/auth/v1/otp"
        """#
      }
      .register()

      let sut = makeSUT()

      let messageID = try await sut.signInWithOTP(
        phone: "+1 202-918-2132",
        options: PhoneOTPOptions(
          shouldCreateUser: true,
          userMetadata: ["custom_key": .string("custom_value")],
          channel: .whatsapp,
          captchaToken: "dummy-captcha"
        )
      )

      #expect(messageID == MessageID(rawValue: "SM123"))
    }

    @Test
    func signInWithOTPUsingPhoneWithoutAMessageID() async throws {
      Mock(
        url: clientURL.appendingPathComponent("otp"),
        statusCode: 200,
        data: [.post: Data("{}".utf8)]
      ).register()
      let sut = makeSUT()

      let messageID = try await sut.signInWithOTP(phone: "+1 202-918-2132")

      #expect(messageID == nil)
    }

    @Test
    func oauthSignInURL() async throws {
      let sut = makeSUT()
      let flow = try await sut.oauthSignInURL(
        .github,
        options: OAuthOptions(
          scopes: ["read", "write"],
          redirectTo: URL(string: "https://dummy-url.com/redirect")!,
          queryItems: [URLQueryItem(name: "extra_key", value: "extra_value")]
        )
      )
      expectNoDifference(
        flow.url,
        URL(
          string:
            "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read%20write&redirect_to=https://dummy-url.com/redirect&code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&extra_key=extra_value"
        )!
      )
    }

    @Test
    func refreshSession() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 33" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"refresh_token\":\"refresh-token\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=refresh_token"
        """#
      }
      .register()

      let sut = makeSUT()
      var session = Session.valid
      session.refreshToken = "refresh-token"
      try await sut.seedSession(session)
      try await sut.refreshSession()
    }

    #if !os(Linux) && !os(Windows) && !os(Android)
      @Test
      func sessionFromURL() async throws {
        Mock(
          url: clientURL.appendingPathComponent("user"),
          ignoreQuery: true,
          statusCode: 200,
          data: [.get: MockData.user]
        )
        .snapshotRequest {
          #"""
          curl \
          	--header "Authorization: bearer accesstoken" \
          	--header "X-Client-Info: auth-swift/0.0.0" \
          	--header "X-Supabase-Api-Version: 2024-01-01" \
          	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
          	"http://localhost:54321/auth/v1/user"
          """#
        }
        .register()

        let currentDate = Date()

        let sut = makeSUT(date: { currentDate })

        let url = URL(
          string:
            "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
        )!

        let result = try await sut.handleRedirect(url)
        let expectedSession = Session(
          accessToken: "accesstoken",
          tokenType: "bearer",
          expiresIn: 60,
          expiresAt: currentDate.addingTimeInterval(60).timeIntervalSince1970,
          refreshToken: "refreshtoken",
          user: User(fromMockNamed: "user")
        )
        expectNoDifference(result, .signedIn(expectedSession, verification: nil))
      }
    #endif

    @Test
    func importSessionWithAFutureExpirationDate() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [.get: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/user"
        """#
      }
      .register()

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let accessToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

      try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }

    @Test
    func importSessionWithAnExpiredToken() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 39" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"refresh_token\":\"dummy-refresh-token\"}" \
        	"http://localhost:54321/auth/v1/token?grant_type=refresh_token"
        """#
      }
      .register()

      let sut = makeSUT()

      let accessToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

      try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }

    @Test
    func verifyOTPUsingEmail() async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 64" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"email\":\"example@mail.com\",\"token\":\"123456\",\"type\":\"magiclink\"}" \
        	"http://localhost:54321/auth/v1/verify"
        """#
      }
      .register()

      let sut = makeSUT()

      let result = try await sut.verifyOTP(
        email: "example@mail.com",
        token: "123456",
        type: .magiclink
      )

      guard case .signedIn(let session) = result else {
        Issue.record("Expected .signedIn, got \(result)")
        return
      }
      #expect(sut.currentSession == session)
    }

    @Test
    func verifyOTPUsingPhone() async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 57" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"phone\":\"+1 202-918-2132\",\"token\":\"123456\",\"type\":\"sms\"}" \
        	"http://localhost:54321/auth/v1/verify"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.verifyOTP(
        phone: "+1 202-918-2132",
        token: "123456",
        type: .sms
      )
    }

    @Test
    func verifyOTPUsingTokenHash() async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 39" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"token_hash\":\"abc-def\",\"type\":\"email\"}" \
        	"http://localhost:54321/auth/v1/verify"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.verifyOTP(
        tokenHash: "abc-def",
        type: .email
      )
    }

    @Test(arguments: [
      (EmailOTPType.recovery, AuthEvent.passwordRecovery),
      (EmailOTPType.emailChange, AuthEvent.signedIn),
      (EmailOTPType.email, AuthEvent.signedIn),
    ])
    func verifyOTPWithTokenHashEmitsTheEventForItsType(
      type: EmailOTPType, event: AuthEvent
    ) async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.verifyOTP(tokenHash: "abc-def", type: type) },
        expectedEvents: [.initialSession, event]
      )
    }

    @Test(arguments: ["email", "phone"])
    func verifyOTPForAChangeOfTheSignedInUserEmitsUserUpdated(channel: String) async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()
      let held = try AuthClient.Configuration.jsonDecoder.decode(
        Session.self, from: MockData.session)
      try await sut.seedSession(held)

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          if channel == "email" {
            try await sut.verifyOTP(tokenHash: "abc-def", type: .emailChange)
          } else {
            try await sut.verifyOTP(phone: "+1 202-918-2132", token: "123456", type: .phoneChange)
          }
        },
        expectedEvents: [.initialSession, .userUpdated]
      )
    }

    @Test
    func verifyOTPWithEmailForRecoveryEmitsPasswordRecovery() async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          try await sut.verifyOTP(email: "example@mail.com", token: "123456", type: .recovery)
        },
        expectedEvents: [.initialSession, .passwordRecovery]
      )
    }

    @Test(arguments: [
      (PhoneOTPType.phoneChange, AuthEvent.signedIn),
      (PhoneOTPType.sms, AuthEvent.signedIn),
    ])
    func verifyOTPWithPhoneEmitsTheEventForItsType(
      type: PhoneOTPType, event: AuthEvent
    ) async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.verifyOTP(phone: "+1 202-918-2132", token: "123456", type: type) },
        expectedEvents: [.initialSession, event]
      )
    }

    @Test
    func verifyOTPForEmailChangeSingleConfirmation() async throws {
      Mock(
        url: clientURL.appendingPathComponent("verify"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.emailChangeSingleConfirmation]
      ).register()

      let sut = makeSUT()

      let result = try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.verifyOTP(tokenHash: "abc-def", type: .emailChange) },
        expectedEvents: [.initialSession]
      )

      #expect(
        result
          == .emailChangePending(
            message:
              "Confirmation link accepted. Please proceed to confirm link sent to the other email"
          )
      )
      #expect(sut.currentSession == nil)
    }

    @Test
    func updateUser() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [.put: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PUT \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 228" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"nonce\":\"abcdef\",\"password\":\"another.pass\",\"phone\":\"+1 202-918-2132\"}" \
        	"http://localhost:54321/auth/v1/user"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      try await sut.updateUser(
        UserAttributes(
          email: "example@mail.com",
          phone: "+1 202-918-2132",
          password: "another.pass",
          nonce: "abcdef",
          userMetadata: ["custom_key": .string("custom_value")]
        )
      )
    }

    @Test
    func resetPassword() async throws {
      Mock(
        url: clientURL.appendingPathComponent("recover"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 179" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"}}" \
        	"http://localhost:54321/auth/v1/recover?redirect_to=https://supabase.com"
        """#
      }
      .register()

      let sut = makeSUT()
      try await sut.resetPassword(
        email: "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }

    @Test
    func pkceExchangeAfterResetPasswordEmitsPasswordRecovery() async throws {
      Mock(
        url: clientURL.appendingPathComponent("recover"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      ).register()
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()

      try await sut.resetPassword(email: "example@mail.com")

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.handleRedirect(URL(string: "https://supabase.com?code=12345")!) },
        expectedEvents: [.initialSession, .passwordRecovery]
      )
    }

    @Test
    func pkceExchangeOfASignInFlowEmitsSignedIn() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()
      _ = try await sut.dependencies.flowStore.start(purpose: .recovery, redirectTo: nil)
      let signIn = try await sut.dependencies.flowStore.start(purpose: .signIn, redirectTo: nil)

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.exchangeCodeForSession("12345", flowID: signIn.flow.id) },
        expectedEvents: [.initialSession, .signedIn]
      )
    }

    @Test
    func pkceExchangeOfAnEmailChangeForTheSignedInUserEmitsUserUpdated() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.session]
      ).register()
      let sut = makeSUT()
      let held = try AuthClient.Configuration.jsonDecoder.decode(
        Session.self, from: MockData.session)
      try await sut.seedSession(held)
      let flow = try await sut.dependencies.flowStore.start(purpose: .emailChange, redirectTo: nil)

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.exchangeCodeForSession("12345", flowID: flow.flow.id) },
        expectedEvents: [.initialSession, .userUpdated]
      )
    }

    @Test
    func emailChangeRequestsStoreAnEmailChangeFlow() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.put: MockData.user]
      ).register()
      Mock(
        url: clientURL.appendingPathComponent("resend"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      ).register()
      let sut = makeSUT()
      try await sut.seedSession(.valid)
      let flows = sut.dependencies.flowStore

      try await sut.updateUser(UserAttributes(email: "new@example.com"))
      #expect(try await flows.pendingFlows().first?.purpose == .emailChange)

      try await sut.resend(email: "example@mail.com", type: .signup)
      #expect(try await flows.pendingFlows().first?.purpose == .signIn)

      try await sut.resend(email: "example@mail.com", type: .emailChange)
      #expect(try await flows.pendingFlows().first?.purpose == .emailChange)
    }

    @Test
    func resendEmail() async throws {
      Mock(
        url: clientURL.appendingPathComponent("resend"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 201" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"type\":\"email_change\"}" \
        	"http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.resend(
        email: "example@mail.com",
        type: .emailChange,
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }

    @Test
    func resendEmailImplicitFlow() async throws {
      Mock(
        url: clientURL.appendingPathComponent("resend"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 201" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"type\":\"email_change\"}" \
        	"http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.resend(
        email: "example@mail.com",
        type: .emailChange,
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }

    @Test
    func resendPhone() async throws {
      Mock(
        url: clientURL.appendingPathComponent("resend"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"message_id": "12345"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 106" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"phone\":\"+1 202-918-2132\",\"type\":\"phone_change\"}" \
        	"http://localhost:54321/auth/v1/resend"
        """#
      }
      .register()

      let sut = makeSUT()

      let messageID = try await sut.resend(
        phone: "+1 202-918-2132",
        type: .phoneChange,
        captchaToken: "captcha-token"
      )

      #expect(messageID == MessageID(rawValue: "12345"))
    }

    @Test
    func deleteUser() async throws {
      let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(id)"),
        statusCode: 204,
        data: [.delete: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 28" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"should_soft_delete\":false}" \
        	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked(secretKey: apiKey)
      try await sut.deleteUser(id: id)
    }

    @Test
    func adminListPasskeysReturnsItems() async throws {
      let userId = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/passkeys"),
        statusCode: 200,
        data: [
          .get: Data(
            """
            [
              {
                "id": "11111111-1111-1111-1111-111111111111",
                "friendly_name": "Work Laptop",
                "created_at": "2024-01-15T10:00:00.000Z",
                "last_used_at": "2024-02-01T08:30:00.000Z"
              },
              {
                "id": "22222222-2222-2222-2222-222222222222",
                "friendly_name": null,
                "created_at": "2024-01-16T10:00:00.000Z",
                "last_used_at": null
              }
            ]
            """.utf8
          )
        ]
      )
      .register()

      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      let passkeys = try await sut.passkeys.list(forUser: userId)

      expectNoDifference(
        passkeys.map(\.id),
        [
          UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
          UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        ]
      )
      expectNoDifference(passkeys[0].friendlyName, "Work Laptop")
      expectNoDifference(passkeys[1].friendlyName, nil)
      expectNoDifference(passkeys[1].lastUsedAt, nil)
    }

    @Test
    func adminDeletePasskey() async throws {
      let userId = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
      let passkeyId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(userId)/passkeys/\(passkeyId)"),
        statusCode: 204,
        data: [.delete: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/admin/users/\#(userId)/passkeys/\#(passkeyId)"
        """#
      }
      .register()

      let sut = AuthAdminClient.mocked(secretKey: apiKey)
      try await sut.passkeys.delete(id: passkeyId, forUser: userId)
    }

    @Test
    func reauthenticate() async throws {
      Mock(
        url: clientURL.appendingPathComponent("reauthenticate"),
        statusCode: 200,
        data: [.get: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/reauthenticate"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      try await sut.reauthenticate()
    }

    @Test
    func unlinkIdentity() async throws {
      let identityId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
      Mock(
        url: clientURL.appendingPathComponent("user/identities/\(identityId.uuidString)"),
        statusCode: 204,
        data: [.delete: Data()]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/user/identities/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      try await sut.unlinkIdentity(
        UserIdentity(
          id: identityId,
          providerUserID: "5923044",
          userID: UUID(),
          provider: .email,
          createdAt: Date(),
          lastSignInAt: Date(),
          updatedAt: Date()
        )
      )
    }

    @Test
    func unlinkIdentityEmitsUserUpdatedWithoutTheIdentity() async throws {
      let identities = try #require(Session.valid.user.identities)
      let unlinked = identities[0]
      Mock(
        url: clientURL.appendingPathComponent("user/identities/\(unlinked.id.uuidString)"),
        statusCode: 200,
        data: [.delete: Data("{}".utf8)]
      ).register()
      let sut = makeSUT()
      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.unlinkIdentity(unlinked) },
        expectedEvents: [.initialSession, .userUpdated]
      )

      expectNoDifference(sut.currentUser?.identities, Array(identities.dropFirst()))
    }

    @Test
    func unlinkIdentityOfAnotherUserEmitsNothing() async throws {
      var identity = try #require(Session.valid.user.identities?.first)
      identity.userID = UUID()
      Mock(
        url: clientURL.appendingPathComponent("user/identities/\(identity.id.uuidString)"),
        statusCode: 200,
        data: [.delete: Data("{}".utf8)]
      ).register()
      let sut = makeSUT()
      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.unlinkIdentity(identity) },
        expectedEvents: [.initialSession]
      )

      expectNoDifference(sut.currentUser, Session.valid.user)
    }

    @Test
    func identitiesReturnsEmptyWhenNull() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [
          .get: Data(
            """
            {
              "id": "859f402d-b3de-4105-a1b9-932836d9193b",
              "aud": "authenticated",
              "identities": null,
              "created_at": "2022-04-09T11:23:45.874827Z",
              "updated_at": "2022-04-09T11:57:01.720803Z"
            }
            """.utf8
          )
        ]
      ).register()
      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let identities = try await sut.identities()

      #expect(identities.isEmpty)
    }

    @Test
    func updateUserMergesIntoCurrentSession() async throws {
      let race = Race()
      let gate = Gate()
      race.answerSignIn { _ in race.issue("signed-in") }
      race.answerRefresh { try Race.ok(race.issue("refreshed")) }
      race.answerUserUpdate(through: gate, with: Race.user(nickname: "updated"))
      let client = race.makeClient()
      var events = client.events().makeAsyncIterator()
      #expect(await events.next()?.event == .initialSession)
      try await client.signIn(email: "a@example.com", password: "secret")
      #expect(await events.next()?.event == .signedIn)

      let update = Task {
        try await client.updateUser(UserAttributes(userMetadata: ["nickname": "updated"]))
      }
      await gate.arrivals(1)
      try await client.refreshSession()
      #expect(await events.next()?.event == .tokenRefreshed)
      gate.open()
      let returnedUser = try await update.value

      #expect(await events.next()?.event == .userUpdated)
      #expect(returnedUser.userMetadata["nickname"] == "updated")
      #expect(client.currentSession?.accessToken == "refreshed-access")
      expectNoDifference(client.currentSession?.user, returnedUser)
    }

    @Test
    func ssoSignInURLUsingDomain() async throws {
      Mock(
        url: clientURL.appendingPathComponent("sso"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"url":"https://supabase.com"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 241" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"domain\":\"supabase.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"redirect_to\":\"https:\/\/supabase.com\",\"skip_http_redirect\":true}" \
        	"http://localhost:54321/auth/v1/sso"
        """#
      }
      .register()

      let sut = makeSUT()

      let flow = try await sut.ssoSignInURL(
        .domain("supabase.com"),
        options: SSOOptions(
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "captcha-token"
        )
      )

      expectNoDifference(flow.url, URL(string: "https://supabase.com")!)
    }

    @Test
    func ssoSignInURLUsingProviderID() async throws {
      Mock(
        url: clientURL.appendingPathComponent("sso"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data(#"{"url":"https://supabase.com"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Content-Length: 270" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"provider_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"redirect_to\":\"https:\/\/supabase.com\",\"skip_http_redirect\":true}" \
        	"http://localhost:54321/auth/v1/sso"
        """#
      }
      .register()

      let sut = makeSUT()

      let flow = try await sut.ssoSignInURL(
        .providerID(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!),
        options: SSOOptions(
          redirectTo: URL(string: "https://supabase.com"),
          captchaToken: "captcha-token"
        )
      )

      expectNoDifference(flow.url, URL(string: "https://supabase.com")!)
    }

    @Test
    func mfaEnrollTOTP() async throws {
      Mock(
        url: clientURL.appendingPathComponent("factors"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000012345",
              "type": "totp",
              "friendly_name": "test",
              "totp": {
                "qr_code": "<svg />",
                "secret": "SECRET",
                "uri": "otpauth://totp/supabase.com:user?secret=SECRET"
              }
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 69" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"factor_type\":\"totp\",\"friendly_name\":\"test\",\"issuer\":\"supabase.com\"}" \
        	"http://localhost:54321/auth/v1/factors"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let enrollment = try await sut.mfa.enrollTOTP(issuer: "supabase.com", friendlyName: "test")

      expectNoDifference(
        enrollment,
        TOTPEnrollment(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000012345")!,
          friendlyName: "test",
          qrCode: "<svg />",
          secret: "SECRET",
          uri: "otpauth://totp/supabase.com:user?secret=SECRET"
        )
      )
    }

    @Test
    func mfaEnrollTOTPWithoutTOTPDataThrowsDecoding() async throws {
      Mock(
        url: clientURL.appendingPathComponent("factors"),
        statusCode: 200,
        data: [.post: Data(#"{"id":"00000000-0000-0000-0000-000000012345","type":"totp"}"#.utf8)]
      )
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let error = await #expect(throws: AuthError.self) {
        try await sut.mfa.enrollTOTP()
      }
      expectNoDifference(error?.kind, .decoding)
    }

    @Test
    func mfaEnrollPhone() async throws {
      Mock(
        url: clientURL.appendingPathComponent("factors"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000012345",
              "type": "phone",
              "friendly_name": "test",
              "phone": "12029182132"
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 72" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"factor_type\":\"phone\",\"friendly_name\":\"test\",\"phone\":\"+1 202-918-2132\"}" \
        	"http://localhost:54321/auth/v1/factors"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let enrollment = try await sut.mfa.enrollPhone("+1 202-918-2132", friendlyName: "test")

      expectNoDifference(
        enrollment,
        PhoneEnrollment(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000012345")!,
          friendlyName: "test",
          phone: "12029182132"
        )
      )
    }

    @Test
    func mfaChallenge() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/challenge"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "type": "totp",
              "expires_at": 12345678
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 2" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{}" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let challenge = try await sut.mfa.challenge(factorID: factorID)

      expectNoDifference(
        challenge,
        MFAChallenge(
          id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
          factorType: .totp,
          expiresAt: Date(timeIntervalSince1970: 12_345_678)
        )
      )
    }

    @Test
    func mfaChallengeWithPhoneType() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/challenge"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "type": "phone",
              "expires_at": 12345678
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 17" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"channel\":\"sms\"}" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let challenge = try await sut.mfa.challenge(factorID: factorID, channel: .sms)

      expectNoDifference(
        challenge,
        MFAChallenge(
          id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
          factorType: .phone,
          expiresAt: Date(timeIntervalSince1970: 12_345_678)
        )
      )
    }

    @Test
    func mfaChallengeWebAuthnReturnsCredentialOptions() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/challenge"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "type": "webauthn",
              "expires_at": 12345678,
              "webauthn": {
                "type": "create",
                "credential_options": {
                  "challenge": "Y2hhbGxlbmdl",
                  "rp": { "id": "example.com", "name": "Example" },
                  "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
                }
              }
            }
            """.utf8
          )
        ]
      )
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let challenge = try await sut.mfa.challenge(
        factorID: factorID, webAuthn: .init(rpId: "example.com"))

      expectNoDifference(challenge.id, UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
      expectNoDifference(challenge.factorType, .webAuthn)
      expectNoDifference(challenge.webauthn?.type, .create)

      let options = challenge.webauthn?.credentialOptions.objectValue
      expectNoDifference(options?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
      expectNoDifference(options?["pubKeyCredParams"]?.arrayValue?.count, 1)
    }

    @Test
    func mfaVerifyReplacesSessionAndEmitsEvent() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/verify"),
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 122" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"code\":\"123456\",\"factor_id\":\"00000000-0000-0000-0000-000000000123\"}" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/verify"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let changes = LockIsolated<[AuthChange]>([])
      let stream = sut.events()
      let collect = Task {
        for await change in stream {
          changes.withValue { $0.append(change) }
          if change.event == .mfaChallengeVerified { break }
        }
      }

      let session = try await sut.mfa.verify(
        factorID: factorID,
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        code: "123456"
      )
      await collect.value

      expectNoDifference(sut.currentSession, session)
      #expect(session.refreshToken != Session.valid.refreshToken)
      expectNoDifference(changes.value.map(\.event), [.initialSession, .mfaChallengeVerified])
    }

    @Test
    func mfaUnenroll() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)"),
        statusCode: 200,
        data: [.delete: Data(#"{"id":"00000000-0000-0000-0000-000000000123"}"#.utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let response = try await sut.mfa.unenroll(factorID: factorID)

      expectNoDifference(response, AuthMFAUnenrollResponse(id: factorID))
    }

    /// A 2xx body that does not decode is a client-side failure, never a server error (#904).
    @Test
    func mfaUnenrollUndecodableSuccessBodyThrowsDecoding() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)"),
        statusCode: 200,
        data: [.delete: Data("{}".utf8)]
      )
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let error = await #expect(throws: AuthError.self) {
        try await sut.mfa.unenroll(factorID: factorID)
      }
      expectNoDifference(error?.kind, .decoding)
    }

    @Test
    func mfaChallengeAndVerify() async throws {
      let factorID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/challenge"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "type": "totp",
              "expires_at": 12345678
            }
            """.utf8
          )
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 2" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{}" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/challenge"
        """#
      }
      .register()

      Mock(
        url: clientURL.appendingPathComponent("factors/\(factorID)/verify"),
        statusCode: 200,
        data: [
          .post: MockData.session
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer accesstoken" \
        	--header "Content-Length: 119" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"challenge_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"code\":\"456\",\"factor_id\":\"00000000-0000-0000-0000-000000000123\"}" \
        	"http://localhost:54321/auth/v1/factors/00000000-0000-0000-0000-000000000123/verify"
        """#
      }
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let session = try await sut.mfa.challengeAndVerify(factorID: factorID, code: "456")

      expectNoDifference(sut.currentSession, session)
    }

    @Test
    func mfaFactorsFetchesUserAndSplitsByStatus() async throws {
      let totpVerified = Factor(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        friendlyName: nil,
        factorType: .totp,
        status: .verified,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
      let phoneUnverified = Factor(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        friendlyName: nil,
        factorType: .phone,
        status: .unverified,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
      let recoveryCodes = Factor(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        friendlyName: "Recovery codes",
        factorType: .recoveryCode,
        status: .verified,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )

      var user = User(fromMockNamed: "user")
      user.factors = [totpVerified, phoneUnverified, recoveryCodes]

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [.get: try AuthClient.Configuration.jsonEncoder.encode(user)]
      )
      .register()

      let sut = makeSUT()

      // The cached user has no factors, so the result can only come from `GET /user`.
      try await sut.seedSession(.valid)

      let factors = try await sut.mfa.factors()

      expectNoDifference(factors.verified, [totpVerified, recoveryCodes])
      expectNoDifference(factors.unverified, [phoneUnverified])
      expectNoDifference(factors.all, [totpVerified, recoveryCodes, phoneUnverified])
    }

    @Test
    func mfaFactorsWhenUserHasNoFactorsReturnsEmpty() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [.get: MockData.user]
      )
      .register()

      let sut = makeSUT()

      try await sut.seedSession(.valid)

      let factors = try await sut.mfa.factors()

      expectNoDifference(factors, MFAFactors(verified: [], unverified: []))
    }

    @Test
    func passkeyRegistrationOptionsDecodeTheChallengeID() async throws {
      Mock(
        url: clientURL.appendingPathComponent("passkeys/registration/options"),
        statusCode: 200,
        data: [
          .post: Data(
            """
            {
              "challenge_id": "e621e1f8-c36c-495a-93fc-0c247a3e6e5f",
              "expires_at": 1705312800,
              "options": {
                "challenge": "Y2hhbGxlbmdl",
                "rp": { "id": "example.com", "name": "Example" },
                "user": { "id": "dXNlci1pZA", "name": "user@example.com", "displayName": "User" },
                "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
              }
            }
            """.utf8
          )
        ]
      )
      .register()

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let options = try await sut.passkeys.registrationOptions()

      expectNoDifference(
        options.challengeID, UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
      expectNoDifference(options.options.objectValue?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
      expectNoDifference(options.options.objectValue?["pubKeyCredParams"]?.arrayValue?.count, 1)
    }

    @Test
    func listPasskeysReturnsItems() async throws {
      Mock(
        url: clientURL.appendingPathComponent("passkeys/"),
        statusCode: 200,
        data: [
          .get: Data(
            """
            [
              {
                "id": "11111111-1111-1111-1111-111111111111",
                "friendly_name": "Work Laptop",
                "created_at": "2024-01-15T10:00:00.000Z",
                "last_used_at": "2024-02-01T08:30:00.000Z"
              },
              {
                "id": "22222222-2222-2222-2222-222222222222",
                "friendly_name": null,
                "created_at": "2024-01-16T10:00:00.000Z",
                "last_used_at": null
              }
            ]
            """.utf8
          )
        ]
      )
      .register()

      let sut = makeSUT()
      try await sut.seedSession(.valid)

      let passkeys = try await sut.passkeys.list()

      expectNoDifference(
        passkeys.map(\.id),
        [
          UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
          UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        ]
      )
      expectNoDifference(passkeys[0].friendlyName, "Work Laptop")
      expectNoDifference(passkeys[1].friendlyName, nil)
      expectNoDifference(passkeys[1].lastUsedAt, nil)
    }

    @Test
    func verifyPasskeyAuthenticationUpdatesSession() async throws {
      Mock(
        url: clientURL.appendingPathComponent("passkeys/authentication/verify"),
        statusCode: 200,
        data: [.post: MockData.session]
      )
      .register()

      let sut = makeSUT()

      let response = try await sut.passkeys.verifyAuthentication(
        challengeID: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        credential: [
          "id": "credential-id",
          "rawId": "cmF3LWlk",
          "type": "public-key",
          "response": [
            "clientDataJSON": "Y2xpZW50LWRhdGE",
            "authenticatorData": "YXV0aA",
            "signature": "c2ln",
          ],
        ]
      )

      expectNoDifference(sut.currentSession, response)
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
      @Test
      @MainActor
      func passkeySignInForwardsBareOptionsAndCommitsSession() async throws {
        Mock(
          url: clientURL.appendingPathComponent("passkeys/authentication/options"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"challenge_id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com","allowCredentials":[{"id":"Y3JlZA","type":"public-key"}]}}"#
                .utf8)
          ]
        )
        .register()
        let verifyBody = Mock(
          url: clientURL.appendingPathComponent("passkeys/authentication/verify"),
          statusCode: 200,
          data: [.post: MockData.session]
        )
        .registerCapturingBody()

        let forwardedOptions = LockIsolated<WebAuthnRequestOptions?>(nil)
        let authenticator = WebAuthnAuthenticator.fake(
          authenticate: { options, _ in
            forwardedOptions.setValue(options)
            return ["id": "cred"]
          }
        )

        let sut = makeSUT()

        let session = try await sut.passkeys.signIn(anchor: nil, authenticator: authenticator)

        expectNoDifference(sut.currentSession, session)
        expectNoDifference(
          forwardedOptions.value,
          WebAuthnRequestOptions(
            rpID: "example.com",
            challenge: Data("challenge".utf8),
            allowedCredentialIDs: [Data("cred".utf8)]
          )
        )
        expectNoDifference(
          verifyBody.value,
          ["challenge_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "credential": ["id": "cred"]]
        )
      }

      @Test
      @MainActor
      func passkeyRegisterForwardsBareOptions() async throws {
        Mock(
          url: clientURL.appendingPathComponent("passkeys/registration/options"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"challenge_id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"},"excludeCredentials":[{"id":"b2xk","type":"public-key"}]}}"#
                .utf8)
          ]
        )
        .register()
        Mock(
          url: clientURL.appendingPathComponent("passkeys/registration/verify"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"id":"11111111-1111-1111-1111-111111111111","friendly_name":"iCloud Keychain","created_at":"2024-01-15T10:00:00.000Z","last_used_at":null}"#
                .utf8)
          ]
        )
        .register()

        let forwardedOptions = LockIsolated<WebAuthnCreationOptions?>(nil)
        let authenticator = WebAuthnAuthenticator.fake(
          register: { options, _ in
            forwardedOptions.setValue(options)
            return ["id": "cred"]
          }
        )

        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let passkey = try await sut.passkeys.register(anchor: nil, authenticator: authenticator)

        expectNoDifference(passkey.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        expectNoDifference(
          forwardedOptions.value,
          WebAuthnCreationOptions(
            rpID: "example.com",
            challenge: Data("challenge".utf8),
            userID: Data("user-id".utf8),
            userName: "u@e.com",
            excludedCredentialIDs: [Data("old".utf8)]
          )
        )
      }

      @Test
      @MainActor
      func mfaEnrollWebAuthnUnwrapsPublicKeyAndSendsCreateType() async throws {
        Mock(
          url: clientURL.appendingPathComponent("factors"),
          statusCode: 200,
          data: [
            .post: Data(#"{"id":"00000000-0000-0000-0000-000000000001","type":"webauthn"}"#.utf8)
          ]
        )
        .register()
        Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/challenge"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"create","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"}}}}}"#
                .utf8)
          ]
        )
        .register()
        let verifyBody = Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/verify"),
          statusCode: 200,
          data: [.post: MockData.session]
        )
        .registerCapturingBody()

        let forwardedRpID = LockIsolated<String?>(nil)
        let authenticator = WebAuthnAuthenticator.fake(
          register: { options, _ in
            forwardedRpID.setValue(options.rpID)
            return ["id": "cred"]
          }
        )

        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let session = try await sut.mfa.enrollWebAuthn(
          friendlyName: "My Passkey",
          anchor: nil,
          authenticator: authenticator
        )

        expectNoDifference(sut.currentSession, session)
        expectNoDifference(forwardedRpID.value, "example.com")
        expectNoDifference(
          verifyBody.value?.objectValue?["webauthn"],
          ["type": "create", "credential_response": ["id": "cred"]]
        )
      }

      @Test
      @MainActor
      func mfaVerifyWebAuthnUnwrapsPublicKeyAndSendsRequestType() async throws {
        Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/challenge"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"request","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}}}"#
                .utf8)
          ]
        )
        .register()
        let verifyBody = Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/verify"),
          statusCode: 200,
          data: [.post: MockData.session]
        )
        .registerCapturingBody()

        let forwardedRpID = LockIsolated<String?>(nil)
        let authenticator = WebAuthnAuthenticator.fake(
          authenticate: { options, _ in
            forwardedRpID.setValue(options.rpID)
            return ["id": "cred"]
          }
        )

        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let session = try await sut.mfa.verifyWebAuthn(
          factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          anchor: nil,
          authenticator: authenticator
        )

        expectNoDifference(sut.currentSession, session)
        expectNoDifference(forwardedRpID.value, "example.com")
        expectNoDifference(
          verifyBody.value?.objectValue?["webauthn"],
          ["type": "request", "credential_response": ["id": "cred"]]
        )
      }

      @Test
      @MainActor
      func mfaVerifyWebAuthnThrowsWhenTheFactorIsNotVerified() async throws {
        Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/challenge"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"create","credential_options":{"publicKey":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"}}}}}"#
                .utf8)
          ]
        )
        .register()
        let verifyBody = Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/verify"),
          statusCode: 200,
          data: [.post: MockData.session]
        )
        .registerCapturingBody()
        let sheetShown = LockIsolated(false)

        let sut = makeSUT()
        try await sut.seedSession(.valid)

        let error = await #expect(throws: AuthError.self) {
          try await sut.mfa.verifyWebAuthn(
            factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            anchor: nil,
            authenticator: .fake(
              register: { _, _ in
                sheetShown.setValue(true)
                return [:]
              },
              authenticate: { _, _ in
                sheetShown.setValue(true)
                return [:]
              }
            )
          )
        }
        #expect(error?.kind == .mfaFactorNotVerified)
        #expect(!sheetShown.value)
        #expect(verifyBody.value == nil)
      }

      @Test
      @MainActor
      func mfaVerifyWebAuthnThrowsDecodingWhenPublicKeyIsMissing() async throws {
        Mock(
          url: clientURL.appendingPathComponent(
            "factors/00000000-0000-0000-0000-000000000001/challenge"),
          statusCode: 200,
          data: [
            .post: Data(
              #"{"id":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","type":"webauthn","expires_at":12345678,"webauthn":{"type":"request","credential_options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}}"#
                .utf8)
          ]
        )
        .register()

        let sut = makeSUT()
        try await sut.seedSession(.valid)

        await #expect {
          try await sut.mfa.verifyWebAuthn(
            factorID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            anchor: nil,
            authenticator: .fake()
          )
        } throws: { error in
          (error as? AuthError)?.kind == .decoding
        }
      }
    #endif

    @Test
    func mfaAssuranceLevelReadsFactorsFromAFreshUser() async throws {
      var session = Session.valid

      session.accessToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJ0b3RwIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfSx7Im1ldGhvZCI6InBob25lIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfV19.OQy2SmA1hcw9V5wrY-bvORjbFh5tWznLIfcMCqPu_6M"

      var user = User(fromMockNamed: "user")
      user.factors = [
        Factor(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          friendlyName: nil,
          factorType: .totp,
          status: .verified,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000),
          updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
      ]

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 200,
        data: [.get: try AuthClient.Configuration.jsonEncoder.encode(user)]
      )
      .register()

      let sut = makeSUT()

      // The cached user has no factors, so `nextLevel` can only come from `GET /user`.
      try await sut.seedSession(session)

      let info = try await sut.mfa.assuranceLevel()

      expectNoDifference(
        info,
        AssuranceLevelInfo(
          currentLevel: .aal1,
          nextLevel: .aal2,
          currentAuthenticationMethods: [
            AMREntry(method: .totp, timestamp: Date(timeIntervalSince1970: 1_516_239_022)),
            AMREntry(method: "phone", timestamp: Date(timeIntervalSince1970: 1_516_239_022)),
          ]
        )
      )
      expectNoDifference(sut.currentSession, session)
    }

    @Test
    func mfaAssuranceLevelWithUndecodableTokenThrowsDecoding() async throws {
      let sut = makeSUT()

      // `Session.valid.accessToken` is not a JWT.
      try await sut.seedSession(.valid)

      let error = await #expect(throws: AuthError.self) {
        try await sut.mfa.assuranceLevel()
      }
      expectNoDifference(error?.kind, .decoding)
    }

    @Test
    func mfaAssuranceLevelWithoutSessionThrowsSessionMissing() async throws {
      let sut = makeSUT()

      let error = await #expect(throws: AuthError.self) {
        try await sut.mfa.assuranceLevel()
      }
      expectNoDifference(error?.kind, .sessionMissing)
    }

    @Test
    func getUserById() async throws {
      let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(id)"),
        statusCode: 200,
        data: [.get: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
        """#
      }
      .register()

      let user = try await sut.user(id: id)

      expectNoDifference(user.id, id)
    }

    @Test
    func adminUpdateUser() async throws {
      let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(id)"),
        statusCode: 200,
        data: [.put: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PUT \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 63" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"phone\":\"1234567890\",\"user_metadata\":{\"full_name\":\"John Doe\"}}" \
        	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
        """#
      }
      .register()

      let attributes = AdminUserAttributes(
        phone: "1234567890",
        userMetadata: [
          "full_name": "John Doe"
        ]
      )

      let user = try await sut.updateUser(id: id, attributes: attributes)

      expectNoDifference(user.id, id)
    }

    @Test
    func createUser() async throws {
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("admin/users"),
        statusCode: 200,
        data: [.post: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 98" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"email\":\"test@example.com\",\"password\":\"password\",\"password_hash\":\"password\",\"phone\":\"1234567890\"}" \
        	"http://localhost:54321/auth/v1/admin/users"
        """#
      }
      .register()

      let attributes = AdminUserAttributes(
        email: "test@example.com",
        password: "password",
        passwordHash: "password",
        phone: "1234567890"
      )

      _ = try await sut.createUser(attributes)
    }

    @Test
    func createUserConfirmingEmailAndPhone() async throws {
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("admin/users"),
        statusCode: 200,
        data: [.post: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 113" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"email\":\"test@example.com\",\"email_confirm\":true,\"password\":\"password\",\"phone\":\"1234567890\",\"phone_confirm\":true}" \
        	"http://localhost:54321/auth/v1/admin/users"
        """#
      }
      .register()

      let attributes = AdminUserAttributes(
        email: "test@example.com",
        confirmsEmail: true,
        password: "password",
        phone: "1234567890",
        confirmsPhone: true
      )

      _ = try await sut.createUser(attributes)
    }

    @Test
    func adminUpdateUserConfirmingEmail() async throws {
      let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("admin/users/\(id)"),
        statusCode: 200,
        data: [.put: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PUT \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 22" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"email_confirm\":true}" \
        	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
        """#
      }
      .register()

      let user = try await sut.updateUser(
        id: id,
        attributes: AdminUserAttributes(confirmsEmail: true)
      )

      expectNoDifference(user.id, id)
    }

    @Test
    func adminInviteUser() async throws {
      let sut = AuthAdminClient.mocked(secretKey: apiKey)

      Mock(
        url: clientURL.appendingPathComponent("invite"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--header "Content-Length: 60" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"data\":{\"full_name\":\"John Doe\"},\"email\":\"test@example.com\"}" \
        	"http://localhost:54321/auth/v1/invite?redirect_to=https://example.com"
        """#
      }
      .register()

      _ = try await sut.inviteUser(
        email: "test@example.com",
        userMetadata: ["full_name": "John Doe"],
        redirectTo: URL(string: "https://example.com")
      )
    }

    @Test
    func removeSessionAndSignoutIfSessionNotFoundErrorReturned() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.user()
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession, .signedOut]
      )

      #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionRevoked))
    }

    @Test
    func signInRejectedAsBannedKeepsStoredSession() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 403,
        data: [
          .post: Data(
            """
            {
              "error_code": "user_banned",
              "msg": "User is banned"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            try await sut.signIn(email: "banned@example.com", password: "secret")
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.errorCode == .userBanned)
          }
        },
        expectedEvents: [.initialSession]
      )

      #expect(sut.currentSession == .valid)
    }

    @Test
    func userWithForeignJWTKeepsStoredSessionIfSessionNotFoundErrorReturned() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.user(jwt: "foreign-access-token")
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession]
      )

      #expect(sut.currentSession == .valid)
    }

    @Test
    func userWithForeignJWTWhileSignedOutKeepsTheSignOutReason() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.user(jwt: "foreign-access-token")
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession]
      )

      #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionMissing))
    }

    @Test
    func userWithStoredJWTRemovesSessionIfSessionNotFoundErrorReturned() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.user(jwt: Session.valid.accessToken)
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession, .signedOut]
      )

      #expect(sut.currentSession == nil)
    }

    @Test
    func importSessionWithForeignTokenKeepsStoredSessionIfSessionNotFoundErrorReturned()
      async throws
    {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      let accessToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.importSession(
              accessToken: accessToken, refreshToken: "dummy-refresh-token")
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession]
      )

      #expect(sut.currentSession == .valid)
    }

    @Test
    func sessionWithURL_implicitFlow_keepsStoredSessionIfSessionNotFoundErrorReturned() async throws
    {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("user"),
        statusCode: 403,
        data: [
          .get: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.valid)

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=foreign-access-token&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.handleRedirect(url)
            Issue.record("Expected failure")
          } catch {
            #expect((error as? AuthError)?.kind == .sessionInvalidated)
          }
        },
        expectedEvents: [.initialSession]
      )

      #expect(sut.currentSession == .valid)
    }

    @Test
    func removeSessionAndSignoutIfRefreshTokenNotFoundErrorReturned() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("token").appendingQueryItems([
          URLQueryItem(name: "grant_type", value: "refresh_token")
        ]),
        statusCode: 403,
        data: [
          .post: Data(
            """
            {
              "error_code": "refresh_token_not_found",
              "message": "Invalid Refresh Token: Refresh Token Not Found"
            }
            """.utf8
          )
        ]
      )
      .register()

      try await sut.seedSession(.expired)

      let expectedEvents = [AuthEvent.initialSession, .signedOut]

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          do {
            _ = try await sut.session()
            Issue.record("Expected failure")
          } catch {
            // `.initialSession` starts a background refresh of the expired session. If it
            // finishes first, nothing is stored when `session` runs.
            let kind = (error as? AuthError)?.kind
            #expect(kind == .sessionInvalidated || kind == .sessionMissing)
          }
        },
        expectedEvents: expectedEvents
      )

      #expect(sut.dependencies.sessionStore.currentStatus == .signedOut(.sessionExpired))
    }

    @Test
    func refreshToken() async throws {
      let sut = makeSUT()

      Mock(
        url: clientURL.appendingPathComponent("token").appendingQueryItems([
          URLQueryItem(name: "grant_type", value: "refresh_token")
        ]),
        statusCode: 200,
        data: [.post: try AuthClient.Configuration.jsonEncoder.encode(Session.valid)]
      )
      .register()

      try await sut.seedSession(.expired)

      let expectedEvents = [AuthEvent.initialSession, .tokenRefreshed]

      try await assertAuthStateChanges(
        sut: sut,
        action: {
          _ = try await sut.session()
        },
        expectedEvents: expectedEvents
      )
    }

    @Test
    func claimsVerifiesLocallyWithoutUserRequest() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
      )
      let jwksRequests = try mockJWKS(signer.jwk)

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "1234567890")
      #expect(result.header.kid == "es256-test-kid")
      #expect(jwksRequests.value == 1)
    }

    @Test
    func claimsCachesJWKSAcrossCalls() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999}"#
      )
      let jwksRequests = try mockJWKS(signer.jwk)

      let sut = makeSUT()

      _ = try await sut.claims(jwt: jwt)
      _ = try await sut.claims(jwt: jwt)

      #expect(jwksRequests.value == 1)
    }

    @Test
    func twoClientsDoNotShareJWKS() async throws {
      let otherURL = URL(string: "http://other-project.localhost/auth/v1")!
      let storageKey = uniqueStorageKey()
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999}"#
      )
      let firstRequests = try mockJWKS(signer.jwk)
      let secondRequests = try mockJWKS(signer.jwk, url: otherURL)

      let first = makeSUT(storageKey: storageKey)
      let second = makeSUT(url: otherURL, storageKey: storageKey)

      _ = try await first.claims(jwt: jwt)
      _ = try await second.claims(jwt: jwt)

      #expect(firstRequests.value == 1)
      #expect(secondRequests.value == 1)
    }

    @Test
    func claimsFallsBackWhenKidUnknown() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"rotated-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999}"#
      )
      let jwksRequests = try mockJWKS(signer.jwk)
      let userRequests = try mockUser()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "1234567890")
      #expect(jwksRequests.value == 1)
      #expect(userRequests.value == 1)
    }

    @Test
    func claimsRejectsMissingExp() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890"}"#
      )
      let jwksRequests = try mockJWKS(signer.jwk)
      let userRequests = try mockUser()

      let sut = makeSUT()

      let error = await #expect(throws: AuthError.self) {
        _ = try await sut.claims(jwt: jwt, options: ClaimsOptions(allowsExpired: true))
      }
      #expect(error?.kind == .jwtVerificationFailed)
      #expect(jwksRequests.value == 0)
      #expect(userRequests.value == 0)
    }

    @Test
    func claimsRejectsExpiredUnlessAllowed() async throws {
      let expiredJWT =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.aN0HLYHkp7nKZp4xWvBaDqSrCFBxk2tq0KZc4BXGqYs"
      let userRequests = try mockUser()

      let sut = makeSUT()

      let error = await #expect(throws: AuthError.self) {
        _ = try await sut.claims(jwt: expiredJWT)
      }
      #expect(error?.kind == .jwtVerificationFailed)
      #expect(error?.message == "JWT has expired")
      #expect(userRequests.value == 0)

      let result = try await sut.claims(
        jwt: expiredJWT,
        options: ClaimsOptions(allowsExpired: true)
      )

      #expect(result.subject == "1234567890")
      #expect(result.expiresAt.timeIntervalSince1970 == 1_516_239_022)
      #expect(userRequests.value == 1)
    }

    @Test
    func claimsPropagatesRefreshError() async throws {
      Mock(
        url: clientURL.appendingPathComponent("token").appendingQueryItems([
          URLQueryItem(name: "grant_type", value: "refresh_token")
        ]),
        statusCode: 400,
        data: [
          .post: Data(
            """
            {
              "error_code": "refresh_token_not_found",
              "message": "Invalid Refresh Token: Refresh Token Not Found"
            }
            """.utf8
          )
        ]
      )
      .register()

      let sut = makeSUT()
      try await sut.seedSession(.expired)

      let refreshError = await #expect(throws: AuthError.self) {
        _ = try await sut.claims()
      }
      #expect(refreshError?.kind == .sessionInvalidated)
      #expect(refreshError?.errorCode == .refreshTokenNotFound)

      let signedOutError = await #expect(throws: AuthError.self) {
        _ = try await sut.claims()
      }
      #expect(signedOutError?.kind == .sessionMissing)
    }

    @Test
    func claimsFallsBackToUserForHS256() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"
      let userRequests = try mockUser()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(userRequests.value == 1)
      #expect(result.subject == "1234567890")
      #expect(result.issuer == "http://localhost:54321/auth/v1")
      #expect(result.audience == ["authenticated"])
      #expect(result.role == "authenticated")
      #expect(result.header.alg == "HS256")
      #expect(result.header.kid == nil)
    }

    @Test
    func claims_withoutJWT_shouldUseSessionAccessToken() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

      var session = Session.valid
      session.accessToken = jwt

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()
      try await sut.seedSession(session)

      let result = try await sut.claims()

      #expect(result.subject == "1234567890")
      #expect(result.role == "authenticated")
    }

    @Test
    func claims_withES256JWTAndJWKS_shouldVerifyLocally() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload:
          #"{"sub":"1234567890","iss":"http://localhost:54321/auth/v1","aud":"authenticated","exp":9999999999,"iat":1516239022,"role":"authenticated"}"#
      )

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 401,
        data: [.get: Data()]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(
        jwt: jwt,
        options: ClaimsOptions(jwks: JWKS(keys: [signer.jwk]))
      )

      #expect(result.subject == "1234567890")
      #expect(result.role == "authenticated")
      #expect(result.header.alg == "ES256")
      #expect(result.header.kid == "es256-test-kid")
    }

    @Test
    func claims_withJWKMissingAlg_shouldVerifyLocally() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload:
          #"{"sub":"1234567890","iss":"http://localhost:54321/auth/v1","aud":"authenticated","exp":9999999999,"iat":1516239022,"role":"authenticated"}"#
      )
      let key = signer.jwk
      let keyWithoutAlg = JWK(
        kty: key.kty,
        keyOps: key.keyOps,
        alg: nil,
        kid: key.kid,
        n: key.n,
        e: key.e,
        crv: key.crv,
        x: key.x,
        y: key.y,
        k: key.k
      )

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 401,
        data: [.get: Data()]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(
        jwt: jwt,
        options: ClaimsOptions(jwks: JWKS(keys: [keyWithoutAlg]))
      )

      #expect(result.subject == "1234567890")
      #expect(result.role == "authenticated")
      #expect(result.header.alg == "ES256")
    }

    @Test
    func claims_withJWKMissingAlgAndMismatchedHeaderAlg_shouldVerifyWithJWKAlgorithm()
      async throws
    {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"RS256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
      )
      let key = signer.jwk
      let keyWithoutAlg = JWK(
        kty: key.kty,
        keyOps: key.keyOps,
        alg: nil,
        kid: key.kid,
        n: key.n,
        e: key.e,
        crv: key.crv,
        x: key.x,
        y: key.y,
        k: key.k
      )

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 401,
        data: [.get: Data()]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(
        jwt: jwt,
        options: ClaimsOptions(jwks: JWKS(keys: [keyWithoutAlg]))
      )

      #expect(result.subject == "1234567890")
      #expect(result.header.alg == "RS256")
    }

    @Test
    func claims_withTamperedES256JWT_shouldThrowWithoutFallback() async throws {
      let signer = ES256TestSigner()
      let jwt = try signer.sign(
        header: #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#,
        payload: #"{"sub":"1234567890","exp":9999999999,"role":"authenticated"}"#
      )
      let parts = jwt.split(separator: ".")
      let tamperedPayload = Base64URL.encode(
        Data(#"{"sub":"1234567890","exp":9999999999,"role":"service_role"}"#.utf8)
      )
      let tamperedJWT = "\(parts[0]).\(tamperedPayload).\(parts[2])"

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()

      let error = await #expect(throws: AuthError.self) {
        _ = try await sut.claims(
          jwt: tamperedJWT,
          options: ClaimsOptions(jwks: JWKS(keys: [signer.jwk]))
        )
      }
      #expect(error?.kind == .jwtVerificationFailed)
      #expect(error?.message == "Invalid JWT signature")
    }

    @Test
    func claims_withES256JWT_shouldFallbackToServerVerification() async throws {
      let jwt =
        "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "1234567890")
      #expect(result.role == "authenticated")
    }

    @Test
    func claims_withNoKidInHeader_shouldFallbackToServerVerification() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ODc2NTQzMjEiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjU0MzIxL2F1dGgvdjEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.YT0NvH-jYKCiN-wrAVcMmTIxZkQ3OtqTVFjJAqGcRuw"

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "987654321")
      #expect(result.role == "authenticated")
    }

    @Test
    func claims_withInvalidJWTStructure_shouldThrowJWTVerificationFailed() async throws {
      let invalidJWT = "invalid.jwt.token"

      let sut = makeSUT()

      do {
        _ = try await sut.claims(jwt: invalidJWT)
        Issue.record("Expected jwtVerificationFailed error")
      } catch let error as AuthError {
        #expect(error.kind == .jwtVerificationFailed)
        #expect(error.message == "Invalid JWT structure")
      } catch {
        Issue.record("Expected AuthError, got \(error)")
      }
    }

    @Test
    func claims_whenServerRejectsJWT_shouldThrowError() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 401,
        data: [
          .get: try! AuthClient.Configuration.jsonEncoder.encode([
            "error": "invalid_token",
            "error_description": "Invalid JWT",
          ])
        ]
      ).register()

      let sut = makeSUT()

      do {
        _ = try await sut.claims(jwt: jwt)
        Issue.record("Expected error from server")
      } catch {
      }
    }

    @Test
    func claims_withComplexClaims_shouldDecodeAllFields() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJuYmYiOjE1MTYyMzkwMjIsImp0aSI6InRlc3QtanRpIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJwaG9uZSI6IisxMjM0NTY3ODkwIn0.dBYm1Y-TfRjPsxw_gXqHB5zGHSH9hXS0OeFN_wL8HbA"

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "1234567890")
      #expect(result.issuer == "http://localhost:54321/auth/v1")
      #expect(result.audience == ["authenticated"])
      #expect(result.expiresAt.timeIntervalSince1970 == 9_999_999_999)
      #expect(result.issuedAt?.timeIntervalSince1970 == 1_516_239_022)
      #expect(result.additionalClaims["nbf"] == 1_516_239_022)
      #expect(result.additionalClaims["jti"] == "test-jti")
      #expect(result.role == "authenticated")
      #expect(result.email == "test@example.com")
      #expect(result.phone == "+1234567890")
    }

    @Test
    func claims_withArrayAudience_shouldDecodeCorrectly() async throws {
      let jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjpbImF1dGhlbnRpY2F0ZWQiLCJzZXJ2aWNlLXJvbGUiXSwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.Jz-lHQoR2VsQ_vX8wKyN7mPxT4aU9cF1bYsHqGdWlIk"

      let user = User(fromMockNamed: "user")

      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
      ).register()

      let sut = makeSUT()

      let result = try await sut.claims(jwt: jwt)

      #expect(result.subject == "1234567890")
      #expect(result.audience == ["authenticated", "service-role"])
    }

    @Test
    func transportFailureIsWrapped() async {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data()],
        requestError: URLError(.notConnectedToInternet)
      )
      .register()

      let sut = makeSUT()

      do {
        try await sut.signIn(email: "a@b.c", password: "secret")
        Issue.record("Expected failure")
      } catch let error as AuthError {
        #expect(error.kind == .transport)
        #expect(error.errorCode == .unknown)
        #expect((error.underlyingError as? URLError)?.code == .notConnectedToInternet)
      } catch {
        Issue.record("Unexpected error \(error)")
      }
    }

    @Test
    func unexpectedResponseBodyIsReported() async {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 502,
        data: [.post: Data("<html>bad gateway</html>".utf8)]
      )
      .register()

      let sut = makeSUT()

      do {
        try await sut.signIn(email: "a@b.c", password: "secret")
        Issue.record("Expected failure")
      } catch let error as AuthError {
        #expect(error.kind == .server)
        #expect(error.errorCode == .unexpectedFailure)
        #expect(error.response?.statusCode == 502)
        #expect(error.response?.body == Data("<html>bad gateway</html>".utf8))
      } catch {
        Issue.record("Unexpected error \(error)")
      }
    }

    @Test
    func undecodableSuccessBodyIsWrapped() async {
      Mock(
        url: clientURL.appendingPathComponent("token"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.post: Data("not json".utf8)]
      )
      .register()

      let sut = makeSUT()

      do {
        try await sut.signIn(email: "a@b.c", password: "secret")
        Issue.record("Expected failure")
      } catch let error as AuthError {
        #expect(error.kind == .decoding)
        #expect(error.underlyingError is DecodingError)
      } catch {
        Issue.record("Unexpected error \(error)")
      }
    }

    private func mockJWKS(_ key: JWK, url: URL = clientURL) throws -> LockIsolated<Int> {
      let fields: [String: String?] = [
        "kty": key.kty, "alg": key.alg, "kid": key.kid, "crv": key.crv, "x": key.x, "y": key.y,
      ]
      let data = try JSONSerialization.data(
        withJSONObject: ["keys": [fields.compactMapValues { $0 }]]
      )
      return countingMock(url: url.appendingPathComponent(".well-known/jwks.json"), data: data)
    }

    private func mockUser() throws -> LockIsolated<Int> {
      let user = User(fromMockNamed: "user")
      return countingMock(
        url: clientURL.appendingPathComponent("user"),
        data: try AuthClient.Configuration.jsonEncoder.encode(user)
      )
    }

    private func countingMock(url: URL, data: Data) -> LockIsolated<Int> {
      let requests = LockIsolated(0)
      var mock = Mock(
        url: url,
        ignoreQuery: true,
        contentType: .json,
        statusCode: 200,
        data: [.get: data]
      )
      mock.onRequestHandler = OnRequestHandler(requestCallback: { _ in
        requests.withValue { $0 += 1 }
      })
      mock.register()
      return requests
    }

    private func makeSUT(
      url: URL = clientURL,
      storageKey: String = uniqueStorageKey(),
      date: @escaping @Sendable () -> Date = { Date() },
      platform: AuthPlatform = .live
    ) -> AuthClient {
      let sessionConfiguration = URLSessionConfiguration.default
      sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
      let session = URLSession(configuration: sessionConfiguration)

      let configuration = AuthClient.Configuration(
        url: url,
        headers: [
          "apikey": apiKey
        ],
        storageKey: storageKey,
        localStorage: storage,
        http: .init(transport: URLSessionTransport(session: session)))

      var pkce = PKCE.live
      pkce.generateCodeVerifier = {
        "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
      }
      pkce.generateCodeChallenge = { _ in
        "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
      }

      return AuthClient(configuration: configuration, date: date, pkce: pkce, platform: platform)
    }

    private func assertAuthStateChanges<T>(
      sut: AuthClient,
      action: () async throws -> T,
      expectedEvents: [AuthEvent],
      expectedSessions: [Session?]? = nil,
      timeout: Duration = .seconds(30),
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) async throws -> T {
      let receivedEvents = LockIsolated([AuthChange]())
      let finished = LockIsolated(false)

      // Cancelled on return: an issue recorded after the test ends crashes Swift Testing.
      let listener = Task {
        for await change in sut.events() {
          if finished.value {
            Issue.record("Received event '\(change.event)' after it finished.")
          }
          receivedEvents.withValue { $0.append(change) }
        }
      }
      defer { listener.cancel() }

      await Task.megaYield()

      let result = try await action()

      try await withTimeout(timeout) {
        defer { finished.setValue(true) }
        while receivedEvents.count < expectedEvents.count {
          try Task.checkCancellation()
          await Task.yield()
        }
      }

      await Task.megaYield()

      expectNoDifference(
        receivedEvents.value.map(\.event),
        expectedEvents,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )

      if let expectedSessions = expectedSessions {
        expectNoDifference(
          receivedEvents.value.map(\.session),
          expectedSessions,
          fileID: fileID,
          filePath: filePath,
          line: line,
          column: column
        )
      }

      return result
    }
  }
}

enum MockData {
  static let listUsersResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "list-users-response", withExtension: "json")!
  )

  static let session = try! Data(
    contentsOf: Bundle.module.url(forResource: "session", withExtension: "json")!
  )

  static let user = try! Data(
    contentsOf: Bundle.module.url(forResource: "user", withExtension: "json")!
  )

  static let anonymousSignInResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "anonymous-sign-in-response", withExtension: "json")!
  )

  static let signUpConfirmationRequired = try! Data(
    contentsOf: Bundle.module.url(forResource: "signup-response", withExtension: "json")!
  )

  static let emailChangeSingleConfirmation = try! Data(
    contentsOf: Bundle.module.url(
      forResource: "email-change-single-confirmation", withExtension: "json"
    )!
  )
}

extension Mock {
  /// Registers the mock and returns the JSON body of the last request it served.
  fileprivate func registerCapturingBody() -> LockIsolated<JSONValue?> {
    let body = LockIsolated<JSONValue?>(nil)
    var mock = self
    mock.onRequestHandler = OnRequestHandler(httpBodyType: JSONValue.self) { _, json in
      body.setValue(json)
    }
    mock.register()
    return body
  }
}

#if canImport(AuthenticationServices) && !os(watchOS)
  extension WebAuthnAuthenticator {
    /// An authenticator whose ceremonies return `{}` unless a test overrides them.
    fileprivate static func fake(
      register:
        @escaping @MainActor @Sendable (WebAuthnCreationOptions, ASPresentationAnchor?)
        async throws -> JSONValue = { _, _ in [:] },
      authenticate:
        @escaping @MainActor @Sendable (WebAuthnRequestOptions, ASPresentationAnchor?)
        async throws -> JSONValue = { _, _ in [:] }
    ) -> Self {
      WebAuthnAuthenticator(register: register, authenticate: authenticate)
    }
  }
#endif
