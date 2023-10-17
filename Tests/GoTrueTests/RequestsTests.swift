//
//  File.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import SnapshotTesting
import XCTest

@testable import GoTrue

struct UnimplementedError: Error {}

final class RequestsTests: XCTestCase {

  var localStorage: InMemoryLocalStorage!

  func testSignUpWithEmailAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signUp(
        email: "example@mail.com",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignUpWithPhoneAndPassword() async {
    let sut = makeSUT()
    await assert {
      try await sut.signUp(
        phone: "+1 202-918-2132",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithEmailAndPassword() async {
    let sut = makeSUT()
    await assert {
      try await sut.signIn(
        email: "example@mail.com",
        password: "the.pass"
      )
    }
  }

  func testSignInWithPhoneAndPassword() async {
    let sut = makeSUT()
    await assert {
      try await sut.signIn(
        phone: "+1 202-918-2132",
        password: "the.pass"
      )
    }
  }

  func testSignInWithIdToken() async {
    let sut = makeSUT()
    await assert {
      try await sut.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .apple,
          idToken: "id-token",
          accessToken: "access-token",
          nonce: "nonce",
          gotrueMetaSecurity: GoTrueMetaSecurity(
            captchaToken: "captcha-token"
          )
        )
      )
    }
  }

  func testSignInWithOTPUsingEmail() async {
    let sut = makeSUT()
    await assert {
      try await sut.signInWithOTP(
        email: "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithOTPUsingPhone() async {
    let sut = makeSUT()
    await assert {
      try await sut.signInWithOTP(
        phone: "+1 202-918-2132",
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testGetOAuthSignInURL() throws {
    let sut = makeSUT()
    let url = try sut.getOAuthSignInURL(
      provider: .github, scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    XCTAssertEqual(
      url,
      URL(
        string:
          "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
      )!
    )
  }

  func testRefreshSession() async {
    let sut = makeSUT()
    await assert {
      try await sut.refreshSession(refreshToken: "refresh-token")
    }
  }

  #if !os(watchOS)
    // Not working on watchOS.
    func testSessionFromURL() async throws {
      let sut = makeSUT(fetch: { request in
        let authorizationHeader = request.allHTTPHeaderFields?["Authorization"]
        XCTAssertEqual(authorizationHeader, "bearer accesstoken")
        return (json(named: "user"), HTTPURLResponse())
      })

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let session = try await sut.session(from: url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: 60,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      XCTAssertEqual(session, expectedSession)
    }
  #endif

  func testSessionFromURLWithMissingComponent() async {
    let sut = makeSUT()
    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    do {
      _ = try await sut.session(from: url)
    } catch let error as URLError {
      XCTAssertEqual(error.code, .badURL)
    } catch {
      XCTFail("Unexpected error thrown: \(error.localizedDescription)")
    }
  }

  func testSetSessionWithAFutureExpirationDate() async throws {
    let sut = makeSUT()
    try localStorage.storeSession(.init(session: .validSession))

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  func testSetSessionWithAExpiredToken() async throws {
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  func testSignOut() async {
    let sut = makeSUT()
    await assert {
      try await sut.signOut()
    }
  }

  func testVerifyOTPUsingEmail() async {
    let sut = makeSUT()
    await assert {
      try await sut.verifyOTP(
        email: "example@mail.com",
        token: "123456",
        type: .magiclink,
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testVerifyOTPUsingPhone() async {
    let sut = makeSUT()
    await assert {
      try await sut.verifyOTP(
        phone: "+1 202-918-2132",
        token: "123456",
        type: .sms,
        captchaToken: "captcha-token"
      )
    }
  }

  func testUpdateUser() async throws {
    let sut = makeSUT()
    try localStorage.storeSession(StoredSession(session: .validSession))
    await assert {
      try await sut.update(
        user: UserAttributes(
          email: "example@mail.com",
          phone: "+1 202-918-2132",
          password: "another.pass",
          emailChangeToken: "123456",
          data: ["custom_key": .string("custom_value")]
        )
      )
    }
  }

  func testResetPasswordForEmail() async {
    let sut = makeSUT()
    await assert {
      try await sut.resetPasswordForEmail(
        "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  private func assert(_ block: () async throws -> Void) async {
    do {
      try await block()
    } catch is UnimplementedError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeSUT(
    record: Bool = false,
    fetch: GoTrueClient.FetchHandler? = nil,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
  ) -> GoTrueClient {
    localStorage = InMemoryLocalStorage()
    let encoder = JSONEncoder.goTrue
    encoder.outputFormatting = .sortedKeys

    return GoTrueClient(
      url: clientURL,
      headers: ["apikey": "dummy.api.key"],
      localStorage: localStorage,
      encoder: encoder,
      fetch: { request in
        DispatchQueue.main.sync {
          assertSnapshot(
            of: request, as: .curl, record: record, file: file, testName: testName, line: line)
        }

        if let fetch {
          return try await fetch(request)
        }

        throw UnimplementedError()
      }
    )
  }
}

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension Session {
  static let validSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}
