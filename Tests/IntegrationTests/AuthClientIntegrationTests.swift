//
//  AuthClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 27/03/24.
//

import ConcurrencyExtras
import Crypto
import CustomDump
import Foundation
import Helpers
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
    let key = serviceRole ? DotEnv.supabaseSecretKey : DotEnv.supabasePublishableKey
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "\(DotEnv.supabaseURL)/auth/v1")!,
        headers: [
          "apikey": key,
          "Authorization": "Bearer \(key)",
        ],
        localStorage: InMemoryLocalStorage()
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

      let metadata: [String: JSONValue] = [
        "test": .integer(42)
      ]

      let result = try await authClient.signUp(
        email: email,
        password: password,
        options: SignUpOptions(userMetadata: metadata)
      )

      guard case .signedIn(let session) = result else {
        Issue.record("Expected .signedIn, got \(result)")
        return
      }
      #expect(authClient.currentSession == session)
      #expect(session.user.email == email)
      #expect(session.user.userMetadata["test"] == 42)

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
        Web3Credentials(
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
        Web3Credentials(
          chain: .ethereum,
          message: message,
          signature: signature
        )
      )

      #expect(!session.accessToken.isEmpty)
    }
  }

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

      let updatedUser = try await authClient.update(
        user: .init(userMetadata: ["test": .integer(42)]))
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
  func signInAnonymouslyStoresUserMetadata() async throws {
    try await expectAuthChangeEvents([.initialSession, .signedIn]) {
      let session = try await authClient.signInAnonymously(
        userMetadata: ["nickname": "guest"]
      )

      #expect(session.user.isAnonymous)
      #expect(session.user.userMetadata["nickname"] == "guest")
      #expect(try await authClient.user().userMetadata["nickname"] == "guest")
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

    var request = URLRequest(url: URL(string: "\(DotEnv.supabaseURL)/rest/v1/rpc/delete_user")!)
    request.httpMethod = "POST"
    request.setValue(DotEnv.supabasePublishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    _ = try await URLSession.shared.data(for: request)

    try await expectAuthChangeEvents([.initialSession, .signedOut]) {
      try await authClient.signOut()
    }
  }

  @Test
  func linkIdentity() async throws {
    try await signUpIfNeededOrSignIn(email: mockEmail(), password: mockPassword())

    let (url, _) = try await authClient.linkIdentityURL(.apple)
    #expect(url.absoluteString.contains("apple.com"))
  }

  @Test(.disabled("Requires secret key and pre-seeded users"))
  func listUsers() async throws {
    let client = Self.makeClient(serviceRole: true)
    let pagination = try await client.admin.listUsers(params: PageParams(perPage: 10))
    #expect(pagination.users.count == 10)
    #expect(pagination.audience == "authenticated")
    #expect(pagination.nextPage == 2)
  }

  @Test
  func adminListPasskeysEmptyForNewUser() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)
    let session = try await authClient.session

    let client = Self.makeClient(serviceRole: true)
    let passkeys = try await client.admin.listPasskeys(forUser: session.user.id)
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
      try await client.admin.deletePasskey(id: UUID(), forUser: session.user.id)
      Issue.record("Expected deletePasskey to throw for a nonexistent passkey")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.response?.statusCode == 404)
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
        #expect(error.kind == .sessionMissing)
      }
      #expect(authClient.currentSession == nil)
    }
  }

  @Test
  func generateLinkSignUp() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()
    let password = mockPassword()

    let link = try await client.admin.generateLink(
      params: .signUp(
        email: email,
        password: password,
        data: ["full_name": "John Doe"]
      )
    )

    expectNoDifference(link.properties.actionLink.path, "/auth/v1/verify")
    expectNoDifference(link.properties.verificationType, .signup)
    expectNoDifference(link.user.email, email)
  }

  @Test
  func generateLinkMagicLink() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()
    let password = mockPassword()

    try await client.admin.createUser(
      attributes: AdminUserAttributes(email: email, password: password)
    )

    let link = try await client.admin.generateLink(params: .magicLink(email: email))

    expectNoDifference(link.properties.verificationType, .magiclink)
  }

  @Test
  func generateLinkRecovery() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()
    let password = mockPassword()

    _ = try await client.signUp(email: email, password: password)

    let link = try await client.admin.generateLink(params: .recovery(email: email))

    expectNoDifference(link.properties.verificationType, .recovery)
  }

  @Test
  func generateLinkInvite() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()

    let link = try await client.admin.generateLink(params: .invite(email: email))

    expectNoDifference(link.properties.verificationType, .invite)
  }

  @Test
  func inviteUserByEmail() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()

    let user = try await client.admin.inviteUserByEmail(email)

    expectNoDifference(user.email, email)
    #expect(user.invitedAt != nil)
  }

  @Test
  func verifyOTPForSecureEmailChange() async throws {
    let client = Self.makeClient(serviceRole: true)
    let email = mockEmail()
    let newEmail = mockEmail()
    let password = mockPassword()

    let signUp = try await client.signUp(email: email, password: password)
    guard case .confirmationRequired(let user) = signUp else {
      Issue.record("Expected .confirmationRequired, got \(signUp)")
      return
    }
    expectNoDifference(user.email, email)
    #expect(user.identities?.isEmpty == false)
    #expect(client.currentSession == nil)

    let currentEmailLink = try await client.admin.generateLink(
      params: .emailChangeCurrent(email: email, newEmail: newEmail)
    )
    let newEmailLink = try await client.admin.generateLink(
      params: .emailChangeNew(email: email, newEmail: newEmail)
    )

    let firstConfirmation = try await client.verifyOTP(
      tokenHash: currentEmailLink.properties.hashedToken,
      type: .emailChange
    )
    guard case .emailChangeConfirmationPending(let confirmation) = firstConfirmation else {
      Issue.record("Expected .emailChangeConfirmationPending, got \(firstConfirmation)")
      return
    }
    #expect(confirmation.code == "200")

    // GoTrue's admin/generate_link response has a bug for `email_change_new`: `hashedToken` is
    // computed from the current email, not the new one, so it never matches what's actually
    // stored. The raw `emailOTP` is correct, so use the email+token overload instead of tokenHash.
    let secondConfirmation = try await client.verifyOTP(
      email: newEmail,
      token: newEmailLink.properties.emailOTP,
      type: .emailChange
    )
    let session = try #require(secondConfirmation.session)
    expectNoDifference(session.user.email, newEmail)
  }

  @Test
  func adminSignOut() async throws {
    let email = mockEmail()
    let password = mockPassword()

    let session = try await signUpIfNeededOrSignIn(email: email, password: password).session
    let accessToken = try #require(session?.accessToken)

    let adminClient = Self.makeClient(serviceRole: true)
    try await adminClient.admin.signOut(jwt: accessToken)
    withExtendedLifetime(adminClient) {}
  }

  @Test
  func wellKnownJWKSServesES256Key() async throws {
    let url = URL(string: "\(DotEnv.supabaseURL)/auth/v1/.well-known/jwks.json")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let jwks = try AuthClient.Configuration.jsonDecoder.decode(JWKS.self, from: data)

    let jwk = try #require(jwks.keys.first { $0.alg == "ES256" })
    expectNoDifference(jwk.kty, "EC")
    expectNoDifference(jwk.crv, "P-256")
    #expect(jwk.kid != nil)

    expectNoDifference(Base64URL.decode(try #require(jwk.x))?.count, 32)
    expectNoDifference(Base64URL.decode(try #require(jwk.y))?.count, 32)

    expectNoDifference(JWTAlgorithm(rawValue: try #require(jwk.alg)), .es256)
    #expect(jwk.p256PublicKey != nil)
  }

  @Test
  func getClaimsWithLiveES256Session() async throws {
    let email = mockEmail()
    let session = try #require(
      try await authClient.signUp(email: email, password: mockPassword()).session
    )

    let decoded = try #require(JWT.decode(session.accessToken))
    expectNoDifference(decoded.header["alg"] as? String, "ES256")
    #expect(decoded.header["kid"] is String)
    expectNoDifference(decoded.signature.count, 64)

    let result = try await authClient.claims()

    expectNoDifference(result.header.alg, "ES256")
    expectNoDifference(result.claims.sub, session.user.id.uuidString.lowercased())
    expectNoDifference(result.claims.email, email)
    expectNoDifference(result.claims.role, "authenticated")
  }

  @Test
  func getClaimsRejectsTamperedLiveES256Token() async throws {
    let session = try #require(
      try await authClient.signUp(email: mockEmail(), password: mockPassword()).session
    )

    let parts = session.accessToken.split(separator: ".")
    var payload = try #require(
      JWT.decodePayload(session.accessToken)
    )
    payload["role"] = "service_role"
    let tamperedPayload = Base64URL.encode(
      try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    )
    let tamperedJWT = "\(parts[0]).\(tamperedPayload).\(parts[2])"

    let error = await #expect(throws: AuthError.self) {
      _ = try await authClient.claims(jwt: tamperedJWT)
    }
    #expect(error?.kind == .jwtVerificationFailed)
    #expect(error?.message == "Invalid JWT signature")
  }

  @discardableResult
  private func signUpIfNeededOrSignIn(
    email: String,
    password: String
  ) async throws -> SignUpResult {
    do {
      let session = try await authClient.signIn(email: email, password: password)
      return .signedIn(session)
    } catch {
      return try await authClient.signUp(email: email, password: password)
    }
  }

  private func mockEmail(length: Int = Int.random(in: 5...10)) -> String {
    var username = ""
    for _ in 0..<length {
      let randomAscii = Int.random(in: 97...122)
      let randomCharacter = Character(UnicodeScalar(randomAscii)!)
      username.append(randomCharacter)
    }
    return "\(username)@supabase.com"
  }

  private func mockPhoneNumber() -> String {
    let countryCode = String(format: "%d", Int.random(in: 1...999))

    let areaCode = String(format: "%03d", Int.random(in: 100...999))

    let subscriberNumber = String(format: "%07d", Int.random(in: 1_000_000...9_999_999))

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

    let deadline = Date().addingTimeInterval(0.5)
    while receivedEvents.value.count < events.count, Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
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
  let privateKey = try P256K.Recovery.PrivateKey(dataRepresentation: bytes(fromHex: privateKeyHex))

  let prefixed = "\u{19}Ethereum Signed Message:\n\(message.utf8.count)\(message)"
  let hash = keccak256(Array(prefixed.utf8))
  let signature = privateKey.signature(for: HashDigest(hash))
  let compact = signature.compactRepresentation

  let v = UInt8(compact.recoveryId) + 27
  return "0x" + hexString(compact.signature) + String(format: "%02x", v)
}

private func bytes(fromHex hex: String) -> [UInt8] {
  var bytes: [UInt8] = []
  var index = hex.startIndex
  while index < hex.endIndex {
    let next = hex.index(index, offsetBy: 2)
    bytes.append(UInt8(hex[index..<next], radix: 16)!)
    index = next
  }
  return bytes
}

private func hexString(_ bytes: some Sequence<UInt8>) -> String {
  bytes.map { String(format: "%02x", $0) }.joined()
}

/// Keccak-256 as Ethereum uses it. This is not the standard `SHA3_256`, which pads with `0x06`
/// instead of `0x01` and gives a different hash.
private func keccak256(_ input: [UInt8]) -> [UInt8] {
  let rate = 136
  var padded = input + [0x01]
  padded += [UInt8](repeating: 0, count: (rate - padded.count % rate) % rate)
  padded[padded.count - 1] |= 0x80

  var state = [UInt64](repeating: 0, count: 25)
  for blockStart in stride(from: 0, to: padded.count, by: rate) {
    for lane in 0..<(rate / 8) {
      for byte in 0..<8 {
        state[lane] ^= UInt64(padded[blockStart + lane * 8 + byte]) << (8 * byte)
      }
    }
    keccakF1600(&state)
  }
  return (0..<32).map { (index: Int) -> UInt8 in
    let shift = UInt64(8 * (index % 8))
    return UInt8(truncatingIfNeeded: state[index / 8] >> shift)
  }
}

private let keccakRoundConstants: [UInt64] = [
  0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
  0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
  0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
  0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
  0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
  0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
]
private let keccakRotations = [
  1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44,
]
private let keccakPiLanes = [
  10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
]

private func keccakF1600(_ state: inout [UInt64]) {
  func rotateLeft(_ value: UInt64, _ count: Int) -> UInt64 {
    (value << count) | (value >> (64 - count))
  }

  for roundConstant in keccakRoundConstants {
    // θ
    var columns = [UInt64](repeating: 0, count: 5)
    for x in 0..<5 {
      for y in stride(from: 0, to: 25, by: 5) {
        columns[x] ^= state[y + x]
      }
    }
    for x in 0..<5 {
      let d = columns[(x + 4) % 5] ^ rotateLeft(columns[(x + 1) % 5], 1)
      for y in stride(from: 0, to: 25, by: 5) {
        state[y + x] ^= d
      }
    }

    // ρ and π
    var carried = state[1]
    for (lane, rotation) in zip(keccakPiLanes, keccakRotations) {
      (state[lane], carried) = (rotateLeft(carried, rotation), state[lane])
    }

    // χ
    for y in stride(from: 0, to: 25, by: 5) {
      let row: [UInt64] = Array(state[y..<(y + 5)])
      for x in 0..<5 {
        state[y + x] = row[x] ^ (~row[(x + 1) % 5] & row[(x + 2) % 5])
      }
    }

    // ι
    state[0] ^= roundConstant
  }
}

/// Checks the hand-written Keccak-256 that signs the Ethereum message in
/// ``AuthClientIntegrationTests/signInWithWeb3Ethereum()``. It needs no local stack.
@Suite struct Keccak256Tests {
  @Test func matchesKnownVectors() {
    #expect(
      hexString(keccak256([]))
        == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    )
    #expect(
      hexString(keccak256(Array("abc".utf8)))
        == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
    )
  }

  @Test func derivesTheEthereumAddressOfTheTestKey() throws {
    let privateKey = try P256K.Signing.PrivateKey(
      dataRepresentation: bytes(
        fromHex: "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318")
    )
    let publicKey = privateKey.publicKey.uncompressedRepresentation.dropFirst()

    #expect(
      hexString(keccak256(Array(publicKey)).suffix(20))
        == "2c7536e3605d9c16a7a3d7b1898e529396a65c23"
    )
  }
}
