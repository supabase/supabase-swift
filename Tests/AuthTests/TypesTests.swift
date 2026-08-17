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
}
