//
//  AuthClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 27/03/24.
//

import ConcurrencyExtras
import Crypto
import CryptoSwift
import CustomDump
import Foundation
import InlineSnapshotTesting
import P256K
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthClientIntegrationTests {
  let authClient = makeClient()

  static func makeClient(serviceRole: Bool = false) -> AuthClient {
    let key = serviceRole ? DotEnv.SUPABASE_SECRET_KEY : DotEnv.SUPABASE_PUBLISHABLE_KEY
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

  @Test
  func multipleAuthInstances() async throws {
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

  @Test
  func signUpAndSignInWithEmail() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn, .signedOut, .signedIn]) {
      let email = mockEmail()
      let password = mockPassword()

      let metadata: [String: AnyJSON] = [
        "test": .integer(42)
      ]

      let response = try await authClient.signUp(
        email: email,
        password: password,
        data: metadata
      )

      #expect(response.session != nil)
      #expect(response.user.email == email)
      #expect(response.user.userMetadata["test"] == 42)

      try await authClient.signOut()

      try await authClient.signIn(email: email, password: password)
    }
  }

  @Test
  func signInWithWeb3Solana() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn]) {
      let privateKey = Curve25519.Signing.PrivateKey()
      let address = base58Encode(privateKey.publicKey.rawRepresentation)
      let issuedAt = ISO8601DateFormatter().string(from: Date())

      let message = """
        localhost:3000 wants you to sign in with your Solana account:
        \(address)

        I accept the Terms of Service

        URI: http://localhost:3000
        Version: 1
        Issued At: \(issuedAt)
        """

      let signature = try privateKey.signature(for: Data(message.utf8))

      let session = try await authClient.signInWithWeb3(
        credentials: Web3Credentials(
          chain: .solana,
          message: message,
          signature: signature.base64EncodedString()
        )
      )

      #expect(!session.accessToken.isEmpty)
    }
  }

  @Test
  func signInWithWeb3Ethereum() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn]) {
      // Throwaway test-only key, never used outside this test, no funds associated.
      let privateKeyHex = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
      let address = "0x2c7536E3605D9C16a7a3D7b1898e529396a65c23"
      let issuedAt = ISO8601DateFormatter().string(from: Date())

      let message = """
        localhost:3000 wants you to sign in with your Ethereum account:
        \(address)

        I accept the Terms of Service

        URI: http://localhost:3000
        Version: 1
        Chain ID: 1
        Nonce: supabaseswiftintegrationtest
        Issued At: \(issuedAt)
        """

      let signature = try signEthereumPersonalMessage(message, privateKeyHex: privateKeyHex)

      let session = try await authClient.signInWithWeb3(
        credentials: Web3Credentials(
          chain: .ethereum,
          message: message,
          signature: signature
        )
      )

      #expect(!session.accessToken.isEmpty)
    }
  }

  //  func testSignUpAndSignInWithPhone() async throws {
  //    try await expectAuthChangeEvents([.initialSession, .signedIn, .signedOut, .signedIn]) {
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

  @Test
  func signInWithEmail_invalidEmail() async throws {
    let email = mockEmail()
    let password = mockPassword()

    do {
      try await authClient.signIn(email: email, password: password)
      Issue.record("Expect failure")
    } catch {
      if let error = error as? AuthError {
        #expect(error.localizedDescription == "Invalid login credentials")
      } else {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  //  func testSignInWithOTP_usingEmail() async throws {
  //    let email = mockEmail()
  //
  //    try await authClient.signInWithOTP(email: email)
  //    try await authClient.verifyOTP(email: email, token: "123456", type: .magiclink)
  //  }

  @Test
  func signOut_otherScope_shouldSignOutLocally() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn]) {
      let email = mockEmail()
      let password = mockPassword()

      try await signUpIfNeededOrSignIn(email: email, password: password)
      try await authClient.signOut(scope: .others)
    }
  }

  @Test
  func reauthenticate() async throws {
    let email = mockEmail()
    let password = mockPassword()

    try await signUpIfNeededOrSignIn(email: email, password: password)
    try await authClient.reauthenticate()
  }

  @Test
  func user() async throws {
    let email = mockEmail()
    let password = mockPassword()

    try await signUpIfNeededOrSignIn(email: email, password: password)
    let user = try await authClient.user()
    #expect(user.email == email)
  }

  @Test
  func userWithCustomJWT() async throws {
    let firstUserSession = try await signUpIfNeededOrSignIn(
      email: mockEmail(),
      password: mockPassword()
    ).session
    let secondUserSession = try await signUpIfNeededOrSignIn(
      email: mockEmail(),
      password: mockPassword()
    )

    let user = try await authClient.user(jwt: firstUserSession?.accessToken)

    #expect(user.id == firstUserSession?.user.id)
    #expect(user.id != secondUserSession.user.id)
  }

  @Test
  func updateUser() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn, .userUpdated]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      let updatedUser = try await authClient.update(user: .init(data: ["test": .integer(42)]))
      #expect(updatedUser.userMetadata["test"] == 42)
    }
  }

  @Test
  func userIdentities() async throws {
    let session = try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())
    let identities = try await authClient.userIdentities()
    expectNoDifference(
      session.user.identities?.map(\.identityId) ?? [],
      identities.map(\.identityId)
    )
  }

  @Test
  func unlinkIdentity_withOnlyOneIdentity() async throws {
    let identities = try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())
      .user.identities
    let identity = try #require(identities?.first)

    do {
      try await authClient.unlinkIdentity(identity)
      Issue.record("Expect failure")
    } catch let error as AuthError {
      #expect(error.errorCode == .singleIdentityNotDeletable)
    }
  }

  @Test
  func resetPasswordForEmail() async throws {
    let email = mockEmail()
    try await authClient.resetPasswordForEmail(email)
  }

  @Test
  func refreshToken() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn, .tokenRefreshed]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      let refreshedSession = try await authClient.refreshSession()
      let currentStoredSession = try await authClient.session

      #expect(currentStoredSession.accessToken == refreshedSession.accessToken)
    }
  }

  @Test
  func signInAnonymous() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn]) {
      try await authClient.signInAnonymously()
    }
  }

  @Test
  func signInAnonymousAndLinkUserWithEmail() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn, .userUpdated]) {
      try await authClient.signInAnonymously()

      let email = mockEmail()
      let user = try await authClient.update(user: UserAttributes(email: email))

      #expect(user.email == email)
    }
  }

  @Test
  func deleteAccountAndSignOut() async throws {
    let response = try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    let session = try #require(response.session)

    var request = URLRequest(url: URL(string: "\(DotEnv.SUPABASE_URL)/rest/v1/rpc/delete_user")!)
    request.httpMethod = "POST"
    request.setValue(DotEnv.SUPABASE_PUBLISHABLE_KEY, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    _ = try await URLSession.shared.data(for: request)

    try await expectAuthChangeEvents([.initialSession, .signedOut]) {
      try await authClient.signOut()
    }
  }

  @Test
  func linkIdentity() async throws {
    try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    try await authClient.linkIdentity(provider: .apple) { url in
      #expect(url.absoluteString.contains("apple.com"))
    }
  }

  @Test(.disabled("Requires secret key and pre-seeded users"))
  func listUsers() async throws {
    let client = Self.makeClient(serviceRole: true)
    let pagination = try await client.admin.listUsers(params: PageParams(perPage: 10))
    #expect(pagination.users.count == 10)
    #expect(pagination.aud == "authenticated")
    #expect(pagination.nextPage == 2)
  }

  @Test
  func adminListPasskeysEmptyForNewUser() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)
    let session = try await authClient.session

    let client = Self.makeClient(serviceRole: true)
    let passkeys = try await client.admin.listPasskeys(userId: session.user.id)
    #expect(passkeys.isEmpty)
  }

  @Test
  func adminDeletePasskeyNotFound() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)
    let session = try await authClient.session

    let client = Self.makeClient(serviceRole: true)
    do {
      try await client.admin.deletePasskey(userId: session.user.id, passkeyId: UUID())
      Issue.record("Expected deletePasskey to throw for a nonexistent passkey")
    } catch let error as AuthError {
      guard case .api(_, _, _, let response) = error else {
        Issue.record("Expected AuthError.api, got \(error)")
        return
      }
      // Backend returns 404 when the passkey doesn't exist or belongs to another user.
      #expect(response.statusCode == 404)
    }
  }

  @Test
  func signOut() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn, .signedOut]) {
      try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

      _ = try await authClient.session
      #expect(authClient.currentSession != nil)

      try await authClient.signOut()

      do {
        _ = try await authClient.session
        Issue.record("Expected to throw AuthError.sessionMissing")
      } catch let error as AuthError {
        #expect(error == .sessionMissing)
      }
      #expect(authClient.currentSession == nil)
    }
  }

  //  func testGenerateLink_signUp() async throws {
  //    let client = Self.makeClient(serviceRole: true)
  //    let email = mockEmail()
  //    let password = mockPassword()
  //
  //    let link = try await client.admin.generateLink(
  //      params: .signUp(
  //        email: email,
  //        password: password,
  //        data: ["full_name": "John Doe"]
  //      )
  //    )
  //
  //    expectNoDifference(link.properties.actionLink.path, "/auth/v1/verify")
  //    expectNoDifference(link.properties.verificationType, .signup)
  //    expectNoDifference(link.user.email, email)
  //  }
  //
  //  func testGenerateLink_magicLink() async throws {
  //    let client = Self.makeClient(serviceRole: true)
  //    let email = mockEmail()
  //    let password = mockPassword()
  //
  //    // first create a user
  //    try await client.admin.createUser(
  //      attributes: AdminUserAttributes(email: email, password: password)
  //    )
  //
  //    // generate a magic link for the created user
  //    let link = try await client.admin.generateLink(params: .magicLink(email: email))
  //
  //    expectNoDifference(link.properties.verificationType, .magiclink)
  //  }

  // func testGenerateLink_recovery() async throws {
  //   let client = Self.makeClient(serviceRole: true)
  //   let email = mockEmail()
  //   let password = mockPassword()

  //   _ = try await client.signUp(email: email, password: password)

  //   let link = try await client.admin.generateLink(params: .recovery(email: email))

  //   expectNoDifference(link.properties.verificationType, .recovery)
  // }

  //  func testGenerateLink_invite() async throws {
  //    let client = Self.makeClient(serviceRole: true)
  //    let email = mockEmail()
  //
  //    let link = try await client.admin.generateLink(params: .invite(email: email))
  //
  //    expectNoDifference(link.properties.verificationType, .invite)
  //  }

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

  private func mockEmail(length: Int = Int.random(in: 5...10)) -> String {
    var username = ""
    for _ in 0..<length {
      let randomAscii = Int.random(in: 97...122)  // ASCII values for lowercase letters
      let randomCharacter = Character(UnicodeScalar(randomAscii)!)
      username.append(randomCharacter)
    }
    return "\(username)@supabase.com"
  }

  private func mockPhoneNumber() -> String {
    // Generate random country code (1 to 3 digits)
    let countryCode = String(format: "%d", Int.random(in: 1...999))

    // Generate random area code (3 digits)
    let areaCode = String(format: "%03d", Int.random(in: 100...999))

    // Generate random subscriber number (7 digits)
    let subscriberNumber = String(format: "%07d", Int.random(in: 1_000_000...9_999_999))

    // Format the phone number in E.164 format
    let phoneNumber = "\(countryCode)\(areaCode)\(subscriberNumber)"

    return phoneNumber
  }

  private func mockPassword(length: Int = 12) -> String {
    let allowedCharacters =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+"
    var password = ""

    for _ in 0..<length {
      let randomIndex = Int.random(in: 0..<allowedCharacters.count)
      let character = allowedCharacters[
        allowedCharacters.index(
          allowedCharacters.startIndex,
          offsetBy: randomIndex
        )
      ]
      password.append(character)
    }

    return password
  }

  private func expectAuthChangeEvents(
    _ events: [AuthChangeEvent],
    block: () async throws -> Void
  ) async rethrows {
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    let token = await authClient.onAuthStateChange { event, _ in
      receivedEvents.withValue {
        $0.append(event)
      }
    }

    try await block()

    // Poll until we've collected the expected number of events or time out.
    let deadline = Date().addingTimeInterval(0.5)
    while receivedEvents.value.count < events.count, Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
    }

    expectNoDifference(events, receivedEvents.value)

    token.remove()
  }
}

private let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

private func base58Encode(_ input: Data) -> String {
  let bytes = Array(input)
  var zerosCount = 0
  for byte in bytes {
    if byte == 0 { zerosCount += 1 } else { break }
  }
  var integerBytes = bytes
  var result = [UInt8]()
  var startIndex = zerosCount
  while startIndex < integerBytes.count {
    var remainder = 0
    for i in startIndex..<integerBytes.count {
      let value = remainder * 256 + Int(integerBytes[i])
      integerBytes[i] = UInt8(value / 58)
      remainder = value % 58
    }
    result.append(UInt8(remainder))
    while startIndex < integerBytes.count, integerBytes[startIndex] == 0 {
      startIndex += 1
    }
  }
  let prefix = String(repeating: "1", count: zerosCount)
  let encoded = String(result.reversed().map { base58Alphabet[Int($0)] })
  return prefix + encoded
}

private func signEthereumPersonalMessage(_ message: String, privateKeyHex: String) throws -> String
{
  let privateKey = try P256K.Recovery.PrivateKey(dataRepresentation: Data(hex: privateKeyHex))

  let prefixed = "\u{19}Ethereum Signed Message:\n\(message.utf8.count)\(message)"
  let hash = SHA3(variant: .keccak256).calculate(for: Array(prefixed.utf8))
  let signature = privateKey.signature(for: HashDigest(hash))
  let compact = signature.compactRepresentation

  let v = UInt8(compact.recoveryId) + 27
  return "0x" + compact.signature.toHexString() + String(format: "%02x", v)
}
