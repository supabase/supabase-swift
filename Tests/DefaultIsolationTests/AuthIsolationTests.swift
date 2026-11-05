//
//  AuthIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 04/11/26.
//

import Foundation
@_spi(Experimental) import Supabase

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

/// Calls every public async Auth API from the main actor, since this target compiles with
/// `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the build
/// fails. `scripts/check-isolation-coverage.sh` checks that each API has a call.
enum AuthIsolationTests {
  /// Arguments the calls below need. Nothing creates one: it only has to type-check.
  struct Inputs {
    var adminUserAttributes: AdminUserAttributes
    var generateLinkParams: GenerateLinkParams
    var createCustomProviderParams: CreateCustomProviderParams
    var updateCustomProviderParams: UpdateCustomProviderParams
    var createOAuthClientParams: CreateOAuthClientParams
    var updateOAuthClientParams: UpdateOAuthClientParams
    var idTokenCredentials: IDTokenCredentials
    var web3Credentials: Web3Credentials
    var ssoTarget: SSOTarget
    var emailOTPType: EmailOTPType
    var phoneOTPType: PhoneOTPType
    var resendEmailType: ResendEmailType
    var resendPhoneType: ResendPhoneType
    var userAttributes: UserAttributes
    var identity: UserIdentity
  }

  static func auth(_ auth: AuthClient, _ inputs: Inputs) async throws {
    let id = UUID()
    let url = URL(string: "myapp://callback")!
    let presenter = ClosurePresenter { url, _ in url }

    await auth.initialization()
    _ = try await auth.session()
    _ = try await auth.signUp(email: "user@example.com", password: "password")
    _ = try await auth.signUp(phone: "+15555550100", password: "password")
    _ = try await auth.signIn(email: "user@example.com", password: "password")
    _ = try await auth.signIn(phone: "+15555550100", password: "password")
    _ = try await auth.signInWithIDToken(inputs.idTokenCredentials)
    _ = try await auth.signInWithWeb3(inputs.web3Credentials)
    _ = try await auth.signInAnonymously()
    try await auth.signInWithOTP(email: "user@example.com")
    _ = try await auth.signInWithOTP(phone: "+15555550100")
    _ = try await auth.ssoSignInURL(inputs.ssoTarget)
    _ = try await auth.signInWithSSO(inputs.ssoTarget, presenter: presenter)
    _ = try await auth.oauthSignInURL(.github)
    _ = try await auth.signInWithOAuth(.github, presenter: presenter)
    #if canImport(AuthenticationServices)
      _ = try await auth.signInWithSSO(inputs.ssoTarget)
      _ = try await auth.signInWithOAuth(.github)
      _ = try await auth.linkIdentity(.github)
    #endif
    _ = try await auth.exchangeCodeForSession("code", flowID: id)
    _ = try await auth.handleRedirect(url)
    _ = try await auth.importSession(accessToken: "jwt", refreshToken: "token")
    try await auth.signOut()
    _ = try await auth.verifyOTP(email: "user@example.com", token: "1", type: inputs.emailOTPType)
    _ = try await auth.verifyOTP(phone: "+15555550100", token: "1", type: inputs.phoneOTPType)
    _ = try await auth.verifyOTP(tokenHash: "hash", type: inputs.emailOTPType)
    try await auth.resend(email: "user@example.com", type: inputs.resendEmailType)
    _ = try await auth.resend(phone: "+15555550100", type: inputs.resendPhoneType)
    try await auth.reauthenticate()
    _ = try await auth.user()
    _ = try await auth.user(jwt: "jwt")
    _ = try await auth.updateUser(inputs.userAttributes)
    _ = try await auth.identities()
    _ = try await auth.linkIdentity(idToken: inputs.idTokenCredentials)
    _ = try await auth.linkIdentityURL(.github)
    _ = try await auth.linkIdentity(.github, presenter: presenter)
    try await auth.unlinkIdentity(inputs.identity)
    try await auth.resetPassword(email: "user@example.com")
    _ = try await auth.refreshSession()
    _ = try await auth.refreshSessionIfNeeded()
    await auth.startAutoRefresh()
    await auth.stopAutoRefresh()
    _ = try await auth.claims()
    _ = try await auth.claims(jwt: "jwt")
  }

  static func mfa(_ mfa: AuthMFA, credential: JSONValue) async throws {
    let id = UUID()

    _ = try await mfa.enrollTOTP()
    _ = try await mfa.enrollPhone("+15555550100")
    _ = try await mfa.enrollWebAuthnFactor()
    _ = try await mfa.challenge(factorID: id)
    _ = try await mfa.challenge(factorID: id, webAuthn: WebAuthnChallengeOptions())
    _ = try await mfa.verify(factorID: id, challengeID: id, code: "123456")
    _ = try await mfa.verify(
      factorID: id, challengeID: id, type: "create", credentialResponse: credential)
    _ = try await mfa.challengeAndVerify(factorID: id, code: "123456")
    _ = try await mfa.unenroll(factorID: id)
    _ = try await mfa.factors()
    _ = try await mfa.assuranceLevel()

    let recoveryCodes = mfa.recoveryCodes
    _ = try await recoveryCodes.status()
    _ = try await recoveryCodes.generate()
    _ = try await recoveryCodes.verify(code: "code")
    _ = try await recoveryCodes.regenerate()
    _ = try await recoveryCodes.unenroll()
  }

  static func passkeys(_ passkeys: AuthPasskeys, credential: JSONValue) async throws {
    let id = UUID()

    _ = try await passkeys.registrationOptions()
    _ = try await passkeys.verifyRegistration(challengeID: id, credential: credential)
    _ = try await passkeys.authenticationOptions()
    _ = try await passkeys.verifyAuthentication(challengeID: id, credential: credential)
    _ = try await passkeys.list()
    _ = try await passkeys.rename(id: id, friendlyName: "Laptop")
    try await passkeys.delete(id: id)
  }

  #if canImport(AuthenticationServices) && !os(watchOS)
    /// `ASPresentationAnchor` is a window, which only the main actor can use.
    static func ceremonies(_ auth: AuthClient, anchor: ASPresentationAnchor) async throws {
      _ = try await auth.passkeys.signIn(anchor: anchor)
      _ = try await auth.passkeys.register(anchor: anchor)
      _ = try await auth.mfa.enrollWebAuthn(anchor: anchor)
      _ = try await auth.mfa.verifyWebAuthn(factorID: UUID(), anchor: anchor)
    }
  #endif

  static func oauthServer(_ oauthServer: AuthOAuthServer) async throws {
    _ = try await oauthServer.authorizationDetails(id: "id")
    _ = try await oauthServer.approveAuthorization(id: "id")
    _ = try await oauthServer.denyAuthorization(id: "id")
    _ = try await oauthServer.listGrants()
    try await oauthServer.revokeGrant(id: UUID())
  }

  static func admin(_ admin: AuthAdminClient, _ inputs: Inputs) async throws {
    let id = UUID()

    _ = try await admin.user(id: id)
    _ = try await admin.createUser(inputs.adminUserAttributes)
    _ = try await admin.updateUser(id: id, attributes: inputs.adminUserAttributes)
    try await admin.deleteUser(id: id)
    _ = try await admin.inviteUser(email: "user@example.com")
    _ = try await admin.listUsers()
    _ = try await admin.generateLink(inputs.generateLinkParams)
    try await admin.signOut(jwt: "jwt")
    var users = admin.users().makeAsyncIterator()
    _ = try await users.next()

    _ = try await admin.mfa.listFactors(forUser: id)
    try await admin.mfa.deleteFactor(id: id, forUser: id)

    _ = try await admin.oauth.listClients()
    _ = try await admin.oauth.createClient(params: inputs.createOAuthClientParams)
    _ = try await admin.oauth.client(id: id)
    _ = try await admin.oauth.updateClient(id: id, params: inputs.updateOAuthClientParams)
    try await admin.oauth.deleteClient(id: id)
    _ = try await admin.oauth.regenerateClientSecret(id: id)

    _ = try await admin.customProviders.list()
    _ = try await admin.customProviders.create(inputs.createCustomProviderParams)
    _ = try await admin.customProviders.provider(identifier: "custom:acme")
    _ = try await admin.customProviders.update(
      identifier: "custom:acme", params: inputs.updateCustomProviderParams)
    try await admin.customProviders.delete(identifier: "custom:acme")

    _ = try await admin.passkeys.list(forUser: id)
    try await admin.passkeys.delete(id: id, forUser: id)
  }

  static func storageAndPresenters() async throws {
    let data = Data("{}".utf8)
    let url = URL(string: "https://example.com")!

    let inMemory = InMemoryAuthStorage()
    try await inMemory.save(data, key: "key")
    _ = try await inMemory.load(key: "key")
    try await inMemory.remove(key: "key")

    #if canImport(Security)
      let keychain = KeychainStorage()
      try await keychain.save(data, key: "key")
      _ = try await keychain.load(key: "key")
      try await keychain.remove(key: "key")
    #endif

    _ = try await ClosurePresenter { url, _ in url }
      .authenticate(url: url, callbackScheme: "myapp")
    #if canImport(AuthenticationServices)
      _ = try await ASWebAuthenticationSessionPresenter()
        .authenticate(url: url, callbackScheme: "myapp")
    #endif
  }
}
