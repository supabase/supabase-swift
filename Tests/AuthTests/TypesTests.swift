//
//  TypesTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Foundation
import Testing

@testable import Auth

@Suite
struct TypesTests {
  private struct FactorStatusContainer: Decodable {
    let status: FactorStatus
  }

  @Test
  func factorStatusDecodesUnknownValue() throws {
    let json = Data(#"{"status":"pending_review"}"#.utf8)
    let decoded = try JSONDecoder().decode(FactorStatusContainer.self, from: json)
    #expect(decoded.status.rawValue == "pending_review")
  }

  @Test
  func factorStatusDecodesKnownValue() throws {
    let json = Data(#"{"status":"verified"}"#.utf8)
    let decoded = try JSONDecoder().decode(FactorStatusContainer.self, from: json)
    #expect(decoded.status == .verified)
  }

  @Test
  func factorStatusStringLiteral() {
    let status: FactorStatus = "custom_status"
    #expect(status.rawValue == "custom_status")
  }

  @Test
  func factorStatusEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(FactorStatus.unverified)
    #expect(String(decoding: data, as: UTF8.self) == "\"unverified\"")
  }

  @Test
  func messagingChannelEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(MessagingChannel.whatsapp)
    #expect(String(decoding: data, as: UTF8.self) == "\"whatsapp\"")
  }

  @Test
  func messagingChannelStringLiteral() {
    let channel: MessagingChannel = "signal"
    #expect(channel.rawValue == "signal")
  }

  @Test
  func providerStringLiteral() {
    let provider: Provider = "custom_provider"
    #expect(provider.rawValue == "custom_provider")
  }

  @Test
  func providerHashability() {
    let provider1: Provider = .apple
    let provider2: Provider = "apple"
    #expect(provider1 == provider2)
    #expect(provider1.hashValue == provider2.hashValue)
  }

  @Test
  func providerOIDCVariantRawValues() {
    #expect(Provider.linkedinOIDC.rawValue == "linkedin_oidc")
    #expect(Provider.slackOIDC.rawValue == "slack_oidc")
  }

  @Test
  func oidcProviderEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(OpenIDConnectCredentials.Provider.apple)
    #expect(String(decoding: data, as: UTF8.self) == "\"apple\"")
  }

  @Test
  func oidcProviderStringLiteral() {
    let provider: OpenIDConnectCredentials.Provider = "custom_oidc_provider"
    #expect(provider.rawValue == "custom_oidc_provider")
  }

  @Test
  func mobileOTPTypeEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(MobileOTPType.phoneChange)
    #expect(String(decoding: data, as: UTF8.self) == "\"phone_change\"")
  }

  @Test
  func mobileOTPTypeStringLiteral() {
    let type: MobileOTPType = "new_channel"
    #expect(type.rawValue == "new_channel")
  }

  @Test
  func mobileOTPTypeHashability() {
    let type1: MobileOTPType = .sms
    let type2: MobileOTPType = "sms"
    #expect(type1 == type2)
  }

  @Test
  func emailOTPTypeEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(EmailOTPType.emailChange)
    #expect(String(decoding: data, as: UTF8.self) == "\"email_change\"")
  }

  @Test
  func emailOTPTypeStringLiteral() {
    let type: EmailOTPType = "new_flow"
    #expect(type.rawValue == "new_flow")
  }

  @Test
  func emailOTPTypeHashability() {
    let type1: EmailOTPType = .signup
    let type2: EmailOTPType = "signup"
    #expect(type1 == type2)
  }

  @Test
  func resendEmailTypeEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(ResendEmailType.emailChange)
    #expect(String(decoding: data, as: UTF8.self) == "\"email_change\"")
  }

  @Test
  func resendEmailTypeStringLiteral() {
    let type: ResendEmailType = "new_resend_kind"
    #expect(type.rawValue == "new_resend_kind")
  }

  @Test
  func resendMobileTypeEncodesAsRawString() throws {
    let data = try JSONEncoder().encode(ResendMobileType.phoneChange)
    #expect(String(decoding: data, as: UTF8.self) == "\"phone_change\"")
  }

  @Test
  func resendMobileTypeStringLiteral() {
    let type: ResendMobileType = "new_resend_kind"
    #expect(type.rawValue == "new_resend_kind")
  }

  @Test
  func signOutScopeStringLiteral() {
    let scope: SignOutScope = "future_scope"
    #expect(scope.rawValue == "future_scope")
  }

  @Test
  func signOutScopeHashability() {
    let scope1: SignOutScope = .global
    let scope2: SignOutScope = "global"
    #expect(scope1 == scope2)
  }

  @Test
  func userDecodesEmptyEmailAndPhoneAsNil() throws {
    let user = try decodeUser(#""email": "", "phone": """#)
    #expect(user.email == nil)
    #expect(user.phone == nil)
  }

  @Test
  func userKeepsNonEmptyEmailAndPhone() throws {
    let user = try decodeUser(#""email": "a@example.com", "phone": "15551234567""#)
    #expect(user.email == "a@example.com")
    #expect(user.phone == "15551234567")
  }

  @Test
  func userDecodesAbsentFactorsAsEmpty() throws {
    let user = try decodeUser(#""is_anonymous": false"#)
    #expect(user.factors == [])
  }

  @Test(arguments: [
    (#""identities": []"#, [UserIdentity]?.some([])),
    (#""identities": null"#, nil),
  ])
  func userDecodesEmptyOrNullIdentities(fields: String, expected: [UserIdentity]?) throws {
    let user = try decodeUser(fields)
    #expect(user.identities == expected)
  }

  @Test
  func identityWithoutIdentityIDFailsDecoding() {
    let json = Data(
      #"""
      {
        "id": "105012345678901234567",
        "user_id": "859f402d-b3de-4105-a1b9-932836d9193b",
        "provider": "google"
      }
      """#.utf8
    )

    #expect(throws: DecodingError.self) {
      try AuthClient.Configuration.jsonDecoder.decode(UserIdentity.self, from: json)
    }
  }

  @Test
  func identityDecodesIdentityID() throws {
    let json = Data(
      #"""
      {
        "id": "105012345678901234567",
        "identity_id": "6c69f399-be1b-467a-9c53-d3753abdd2df",
        "user_id": "859f402d-b3de-4105-a1b9-932836d9193b",
        "provider": "google"
      }
      """#.utf8
    )

    let identity = try AuthClient.Configuration.jsonDecoder.decode(UserIdentity.self, from: json)

    #expect(identity.identityId == UUID(uuidString: "6c69f399-be1b-467a-9c53-d3753abdd2df"))
  }

  @Test
  func amrEntryReadsObjectsAndStrings() {
    let object: [String: Any] = ["method": "totp", "timestamp": 1_700_000_100.0]

    #expect(
      AMREntry(value: object, issuedAt: 1_700_000_000)
        == AMREntry(method: "totp", timestamp: 1_700_000_100)
    )
    #expect(
      AMREntry(value: "pwd", issuedAt: 1_700_000_000)
        == AMREntry(method: "pwd", timestamp: 1_700_000_000)
    )
    #expect(AMREntry(value: "pwd", issuedAt: nil) == nil)
    #expect(AMREntry(value: 42, issuedAt: 1_700_000_000) == nil)
  }

  private func decodeUser(_ fields: String) throws -> User {
    let json = """
      {
        "id": "859f402d-b3de-4105-a1b9-932836d9193b",
        "aud": "authenticated",
        "created_at": "2026-09-22T10:42:45Z",
        "updated_at": "2026-09-22T10:42:45Z",
        \(fields)
      }
      """
    return try AuthClient.Configuration.jsonDecoder.decode(User.self, from: Data(json.utf8))
  }
}
