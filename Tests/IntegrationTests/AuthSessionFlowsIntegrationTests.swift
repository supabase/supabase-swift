//
//  AuthSessionFlowsIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 16/11/26.
//

import Crypto
import Foundation
import Helpers
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

/// Session refresh, a direct PKCE code exchange and passkey management, against the local stack.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthSessionFlowsIntegrationTests {
  static let password = "The.Pa55word!"

  let auth = try! AuthClientIntegrationTests.makeClient()
  let admin = AuthClientIntegrationTests.makeAdminClient()

  // MARK: - refreshSessionIfNeeded

  @Test
  func refreshSessionIfNeededRefreshesOnlyPastHalfTheLifetime() async throws {
    _ = try await auth.signUp(email: mockEmail(), password: Self.password)
    let signedIn = try await auth.session()

    // Received 60% of its lifetime ago: not expired, but due for a refresh.
    let storage = InMemoryTestStorage()
    let key = "sb-refresh-if-needed-\(UUID().uuidString)-auth-token"
    let receivedAt = Date().addingTimeInterval(-signedIn.expiresIn.timeInterval * 0.6)
    try storage.store(
      key: key, value: PersistedSessionCodec.encode(signedIn.received(at: receivedAt)))
    let client = try makeClient(storage: storage, storageKey: key)

    let refreshed = try #require(try await client.refreshSessionIfNeeded())
    #expect(refreshed.user.id == signedIn.user.id)
    #expect(refreshed.refreshToken != signedIn.refreshToken)

    let again = try await client.refreshSessionIfNeeded()
    #expect(again?.refreshToken == refreshed.refreshToken)
  }

  @Test
  func refreshSessionIfNeededWithoutASessionReturnsNil() async throws {
    let client = try makeClient(
      storage: InMemoryTestStorage(), storageKey: "sb-no-session-\(UUID().uuidString)")
    #expect(try await client.refreshSessionIfNeeded() == nil)
  }

  // MARK: - exchangeCodeForSession

  /// A magic link in the PKCE flow redirects with a `code`, which the client exchanges itself.
  @Test
  func exchangeCodeForSessionSignsInWithTheCodeFromAMagicLink() async throws {
    let email = mockEmail()
    try await admin.createUser(
      AdminCreateUser(email: email, password: Self.password, confirmsEmail: true))

    try await auth.signInWithOTP(
      email: email, options: EmailOTPOptions(redirectTo: URL(string: "http://localhost:3000")!))
    let flow = try #require(try await auth.dependencies.flowStore.pendingFlows().first)
    let link = try await MailCatcher().latestLink(to: email)
    let location = try await redirectLocation(of: link)
    let code = try #require(
      URLComponents(url: location, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "code" }?.value)

    let session = try await auth.exchangeCodeForSession(code, flowID: flow.id)

    #expect(session.user.email == email)
    #expect(auth.currentSession == session)
    #expect(try await auth.dependencies.flowStore.pendingFlows().isEmpty)
    await #expect(throws: AuthError.self) { try await auth.exchangeCodeForSession(code) }
  }

  // MARK: - Passkeys

  /// Registers a passkey with a software authenticator ("none" attestation), then renames it.
  @Test
  func renameAPasskey() async throws {
    _ = try await auth.signUp(email: mockEmail(), password: Self.password)

    let options = try await auth.passkeys.registrationOptions()
    let challenge = try #require(options.options.objectValue?["challenge"]?.stringValue)
    let registered = try await auth.passkeys.verifyRegistration(
      challengeID: options.challengeID,
      credential: SoftwareAuthenticator().registrationCredential(challenge: challenge)
    )

    let renamed = try await auth.passkeys.rename(id: registered.id, friendlyName: "Work laptop")
    #expect(renamed.id == registered.id)
    #expect(renamed.friendlyName == "Work laptop")
    let listed = try await auth.passkeys.list()
    #expect(listed.map(\.id) == [registered.id])
    #expect(listed.map(\.friendlyName) == ["Work laptop"])

    try await auth.passkeys.delete(id: registered.id)
  }

  // MARK: - Helpers

  private func makeClient(storage: InMemoryTestStorage, storageKey: String) throws -> AuthClient {
    try AuthClient(
      configuration: AuthClient.Configuration(
        url: AuthClientIntegrationTests.authURL,
        storageKey: storageKey,
        headers: [
          .apikey: DotEnv.supabasePublishableKey,
          .authorization: "Bearer \(DotEnv.supabasePublishableKey)",
        ],
        storage: storage,
        autoRefresh: .manual
      )
    )
  }

  private func mockEmail() -> String {
    "session-flows-\(UUID().uuidString.lowercased())@supabase.com"
  }
}

/// A WebAuthn authenticator in software, for the relying party in `config.toml`
/// (`localhost`, origin `http://localhost:3000`). It answers a registration with a P-256 key and
/// a "none" attestation, which Auth accepts without a certificate chain.
private struct SoftwareAuthenticator {
  let key = P256.Signing.PrivateKey()
  let credentialID = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

  func registrationCredential(challenge: String) -> JSONValue {
    let clientData = Data(
      #"{"type":"webauthn.create","challenge":"\#(challenge)","origin":"http://localhost:3000","crossOrigin":false}"#
        .utf8)
    let id = Base64URL.encode(credentialID)
    return [
      "id": .string(id),
      "rawId": .string(id),
      "type": "public-key",
      "clientExtensionResults": [:],
      "response": [
        "clientDataJSON": .string(Base64URL.encode(clientData)),
        "attestationObject": .string(Base64URL.encode(attestationObject())),
      ],
    ]
  }

  /// `{"fmt": "none", "attStmt": {}, "authData": …}` in CBOR.
  private func attestationObject() -> Data {
    var cbor = Data([0xA3])
    cbor.append(CBOR.text("fmt"))
    cbor.append(CBOR.text("none"))
    cbor.append(CBOR.text("attStmt"))
    cbor.append(0xA0)
    cbor.append(CBOR.text("authData"))
    cbor.append(CBOR.bytes(authenticatorData()))
    return cbor
  }

  private func authenticatorData() -> Data {
    var data = Data(SHA256.hash(data: Data("localhost".utf8)))
    // User present, user verified, attested credential data included.
    data.append(0x45)
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(Data(count: 16))  // AAGUID
    data.append(contentsOf: [UInt8(credentialID.count >> 8), UInt8(credentialID.count & 0xFF)])
    data.append(credentialID)
    data.append(coseKey())
    return data
  }

  /// The public key as a COSE EC2 key: `{1: 2, 3: -7, -1: 1, -2: x, -3: y}`.
  private func coseKey() -> Data {
    let point = key.publicKey.x963Representation
    let x = point.dropFirst().prefix(32)
    let y = point.suffix(32)
    var cbor = Data([0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01])
    cbor.append(0x21)
    cbor.append(CBOR.bytes(Data(x)))
    cbor.append(0x22)
    cbor.append(CBOR.bytes(Data(y)))
    return cbor
  }
}

/// The few CBOR items the authenticator above writes.
private enum CBOR {
  static func text(_ string: String) -> Data {
    let utf8 = Data(string.utf8)
    return header(major: 3, length: utf8.count) + utf8
  }

  static func bytes(_ data: Data) -> Data {
    header(major: 2, length: data.count) + data
  }

  private static func header(major: UInt8, length: Int) -> Data {
    let type = major << 5
    switch length {
    case 0..<24: return Data([type | UInt8(length)])
    case 24..<256: return Data([type | 24, UInt8(length)])
    default: return Data([type | 25, UInt8(length >> 8), UInt8(length & 0xFF)])
    }
  }
}
