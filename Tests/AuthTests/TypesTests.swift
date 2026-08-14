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

  private struct MessagingChannelContainer: Decodable {
    let channel: MessagingChannel
  }

  @Test
  func messagingChannelDecodesUnknownValue() throws {
    let json = Data(#"{"channel":"telegram"}"#.utf8)
    let decoded = try JSONDecoder().decode(MessagingChannelContainer.self, from: json)
    #expect(decoded.channel.rawValue == "telegram")
  }

  @Test
  func messagingChannelDecodesKnownValue() throws {
    let json = Data(#"{"channel":"whatsapp"}"#.utf8)
    let decoded = try JSONDecoder().decode(MessagingChannelContainer.self, from: json)
    #expect(decoded.channel == .whatsapp)
  }

  @Test
  func messagingChannelStringLiteral() {
    let channel: MessagingChannel = "signal"
    #expect(channel.rawValue == "signal")
  }

  private struct ProviderContainer: Decodable {
    let provider: Provider
  }

  @Test
  func providerDecodesUnknownValue() throws {
    let json = Data(#"{"provider":"threads_2027"}"#.utf8)
    let decoded = try JSONDecoder().decode(ProviderContainer.self, from: json)
    #expect(decoded.provider.rawValue == "threads_2027")
  }

  @Test
  func providerDecodesKnownValue() throws {
    let json = Data(#"{"provider":"apple"}"#.utf8)
    let decoded = try JSONDecoder().decode(ProviderContainer.self, from: json)
    #expect(decoded.provider == .apple)
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

  private struct OIDCProviderContainer: Decodable {
    let provider: OpenIDConnectCredentials.Provider
  }

  @Test
  func oidcProviderDecodesUnknownValue() throws {
    let json = Data(#"{"provider":"threads_2027"}"#.utf8)
    let decoded = try JSONDecoder().decode(OIDCProviderContainer.self, from: json)
    #expect(decoded.provider.rawValue == "threads_2027")
  }

  @Test
  func oidcProviderDecodesKnownValue() throws {
    let json = Data(#"{"provider":"apple"}"#.utf8)
    let decoded = try JSONDecoder().decode(OIDCProviderContainer.self, from: json)
    #expect(decoded.provider == .apple)
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
