//
//  AuthClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 27/03/24.
//

@testable import Auth
import ConcurrencyExtras
import CustomDump
import TestHelpers
import InlineSnapshotTesting
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthClientIntegrationTests: XCTestCase {
  let authClient = makeClient()

  static func makeClient(serviceRole: Bool = false) -> AuthClient {
    let key = serviceRole ? DotEnv.SUPABASE_SERVICE_ROLE_KEY : DotEnv.SUPABASE_ANON_KEY
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "\(DotEnv.SUPABASE_URL)/auth/v1")!,
        headers: [
          "apikey": key,
          "Authorization": "Bearer \(key)",
        ],
        localStorage: InMemoryLocalStorage(),
        logger: nil
      )
    )
  }

  func testMultipleAuthInstances() async throws {
    try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    let client2 = Self.makeClient()

    let sessionFromClient1 = try await authClient.session
    let sessionFromClient2 = try await client2.setSession(
      accessToken: sessionFromClient1.accessToken,
      refreshToken: sessionFromClient1.refreshToken
    )

    expectNoDifference(sessionFromClient1.accessToken, sessionFromClient2.accessToken)
    expectNoDifference(sessionFromClient1.refreshToken, sessionFromClient2.refreshToken)
    expectNoDifference(sessionFromClient1.expiresAt, sessionFromClient2.expiresAt)
  }

  func testSignUpAndSignInWithEmail() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .signedOut, .signedIn]) {
      let email = mockEmail()
      let password = mockPassword()

      let metadata: [String: AnyJSON] = [
        "test": .integer(42),
      ]

      let response = try await authClient.signUp(
        email: email,
        password: password,
        data: metadata
      )

      XCTAssertNotNil(response.session)
      XCTAssertEqual(response.user.email, email)
      XCTAssertEqual(response.user.userMetadata["test"], 42)

      try await authClient.signOut()

      try await authClient.signIn(email: email, password: password)
    }
  }

  func testSignUpWithWeakPassword() async {
    do {
      try await authClient.signUp(email: mockEmail(), password: "weak-password")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        #"""
        ▿ AuthError
          ▿ weakPassword: (2 elements)
            - message: "Password should contain at least one character of each: abcdefghijklmnopqrstuvwxyz, ABCDEFGHIJKLMNOPQRSTUVWXYZ, 0123456789, !@#$%^&*()_+-=[]{};\':\"|<>?,./`~."
            ▿ reasons: 1 element
              - "characters"

        """#
      }
    }
  }

//  func testSignUpAndSignInWithPhone() async throws {
//    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .signedOut, .signedIn]) {
//      let phone = mockPhoneNumber()
//      let password = mockPassword()
//      let metadata: [String: AnyJSON] = [
//        "test": .integer(42),
//      ]
//      let response = try await authClient.signUp(phone: phone, password: password, data: metadata)
//      XCTAssertNotNil(response.session)
//      XCTAssertEqual(response.user.phone, phone)
//      XCTAssertEqual(response.user.userMetadata["test"], 42)
//
//      try await authClient.signOut()
//
//      try await authClient.signIn(phone: phone, password: password)
//    }
//  }

  func testSignInWithEmail_invalidEmail() async throws {
    let email = mockEmail()
    let password = mockPassword()

    do {
      try await authClient.signIn(email: email, password: password)
      XCTFail("Expect failure")
    } catch {
      if let error = error as? AuthError {
        XCTAssertEqual(error.localizedDescription, "Invalid login credentials")
      } else {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

//  func testSignInWithOTP_usingEmail() async throws {
//    let email = mockEmail()
//
//    try await authClient.signInWithOTP(email: email)
//    try await authClient.verifyOTP(email: email, token: "123456", type: .magiclink)
//  }

  func testSignOut_otherScope_shouldSignOutLocally() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn]) {
      let email = mockEmail()
      let password = mockPassword()

      try await signUpIfNeededOrSignIn(email: email, password: password)
      try await authClient.signOut(scope: .others)
    }
  }

  func testReauthenticate() async throws {
    let email = mockEmail()
    let password = mockPassword()

    try await signUpIfNeededOrSignIn(email: email, password: password)
    try await authClient.reauthenticate()
  }

  func testUser() async throws {
    let email = mockEmail()
    let password = mockPassword()

    try await signUpIfNeededOrSignIn(email: email, password: password)
    let user = try await authClient.user()
    XCTAssertEqual(user.email, email)
  }

  func testUserWithCustomJWT() async throws {
    let firstUserSession = try await signUpIfNeededOrSignIn(
      email: mockEmail(),
      password: mockPassword()
    ).session
    let secondUserSession = try await signUpIfNeededOrSignIn(
      email: mockEmail(),
      password: mockPassword()
    )

    let user = try await authClient.user(jwt: firstUserSession?.accessToken)

    XCTAssertEqual(user.id, firstUserSession?.user.id)
    XCTAssertNotEqual(user.id, secondUserSession.user.id)
  }

  func testUpdateUser() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .userUpdated]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      let updatedUser = try await authClient.update(user: .init(data: ["test": .integer(42)]))
      XCTAssertEqual(updatedUser.userMetadata["test"], 42)
    }
  }

  func testUnlinkIdentity_withOnlyOneIdentity() async throws {
    let identities = try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())
      .user.identities
    let identity = try XCTUnwrap(identities?.first)

    do {
      try await authClient.unlinkIdentity(identity)
      XCTFail("Expect failure")
    } catch {
      if let error = error as? AuthError {
        XCTAssertEqual(
          error.localizedDescription,
          "User must have at least 1 identity after unlinking"
        )
      } else {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testResetPasswordForEmail() async throws {
    let email = mockEmail()
    try await authClient.resetPasswordForEmail(email)
  }

  func testRefreshToken() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .tokenRefreshed]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      let refreshedSession = try await authClient.refreshSession()
      let currentStoredSession = try await authClient.session

      XCTAssertEqual(currentStoredSession.accessToken, refreshedSession.accessToken)
    }
  }

  func testSignInAnonymous() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn]) {
      try await authClient.signInAnonymously()
    }
  }

  func testSignInAnonymousAndLinkUserWithEmail() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .userUpdated]) {
      try await authClient.signInAnonymously()

      let email = mockEmail()
      let user = try await authClient.update(user: UserAttributes(email: email))

      XCTAssertEqual(user.email, email)
    }
  }

  func testDeleteAccountAndSignOut() async throws {
    let response = try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    let session = try XCTUnwrap(response.session)

    var request = URLRequest(url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1/rpc/delete_user")!)
    request.httpMethod = "POST"
    request.setValue(DotEnv.SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    _ = try await URLSession.shared.data(for: request)

    try await XCTAssertAuthChangeEvents([.initialSession, .signedOut]) {
      try await authClient.signOut()
    }
  }

  func testLinkIdentity() async throws {
    try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    try await authClient.linkIdentity(provider: .apple) { url in
      XCTAssertTrue(url.absoluteString.contains("apple.com"))
    }
  }

  func testListUsers() async throws {
    let client = Self.makeClient(serviceRole: true)
    let pagination = try await client.admin.listUsers(params: PageParams(perPage: 10))
    XCTAssertEqual(pagination.users.count, 10)
    XCTAssertEqual(pagination.aud, "authenticated")
    XCTAssertEqual(pagination.nextPage, 2)
  }

  func testSignOut() async throws {
    try await XCTAssertAuthChangeEvents([.initialSession, .signedIn, .signedOut]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      _ = try await authClient.session
      XCTAssertNotNil(authClient.currentSession)

      try await authClient.signOut()

      do {
        _ = try await authClient.session
        XCTFail("Expected to throw AuthError.sessionMissing")
      } catch let error as AuthError {
        XCTAssertEqual(error, .sessionMissing)
      }
      XCTAssertNil(authClient.currentSession)
    }
  }

  @discardableResult
  private func signUpIfNeededOrSignIn(
    email: String,
    password: String
  ) async throws -> AuthResponse {
    do {
      let session = try await authClient.signIn(email: email, password: password)
      return .session(session)
    } catch {
      return try await authClient.signUp(email: email, password: password)
    }
  }

  private func mockEmail(length: Int = Int.random(in: 5 ... 10)) -> String {
    var username = ""
    for _ in 0 ..< length {
      let randomAscii = Int.random(in: 97 ... 122) // ASCII values for lowercase letters
      let randomCharacter = Character(UnicodeScalar(randomAscii)!)
      username.append(randomCharacter)
    }
    return "\(username)@supabase.com"
  }

  private func mockPhoneNumber() -> String {
    // Generate random country code (1 to 3 digits)
    let countryCode = String(format: "%d", Int.random(in: 1 ... 999))

    // Generate random area code (3 digits)
    let areaCode = String(format: "%03d", Int.random(in: 100 ... 999))

    // Generate random subscriber number (7 digits)
    let subscriberNumber = String(format: "%07d", Int.random(in: 1000000 ... 9999999))

    // Format the phone number in E.164 format
    let phoneNumber = "\(countryCode)\(areaCode)\(subscriberNumber)"

    return phoneNumber
  }

  private func mockPassword(length: Int = 12) -> String {
    let allowedCharacters = [
      "abcdefghijklmnopqrstuvwxyz",
      "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
      "0123456789",
      "!@#$%^&*()_+-=[]{};\':\"|<>?,./`~.",
    ]

    var password = ""

    while password.count < length {
      for characterSet in allowedCharacters {
        let randomIndex = Int.random(in: 0 ..< characterSet.count)
        let character = characterSet[characterSet.index(
          characterSet.startIndex,
          offsetBy: randomIndex
        )]
        password.append(character)
      }
    }

    return password
  }

  private func XCTAssertAuthChangeEvents(
    _ events: [AuthChangeEvent],
    function: StaticString = #function,
    block: () async throws -> Void
  ) async rethrows {
    let expectation = expectation(description: "\(function)-onAuthStateChange")
    expectation.expectedFulfillmentCount = events.count

    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    let token = await authClient.onAuthStateChange { event, _ in
      receivedEvents.withValue {
        $0.append(event)
      }

      expectation.fulfill()
    }

    try await block()

    await fulfillment(of: [expectation], timeout: 0.5)

    expectNoDifference(events, receivedEvents.value)

    token.remove()
  }
}
