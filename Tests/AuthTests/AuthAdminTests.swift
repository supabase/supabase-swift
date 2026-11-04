//
//  AuthAdminTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 30/09/26.
//

import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthAdminTests {
  @Test
  func sendsTheServiceRoleKeyOnEveryRequest() async throws {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
    let admin = AuthAdminClient.testing(serviceRoleKey: "secret.key", http: transport)

    let id = UUID()
    try await admin.deleteUser(id: id)

    let request = try #require(transport.requests.first?.head)
    #expect(request.method == .delete)
    #expect(request.url?.path == "/auth/v1/admin/users/\(id)")
    #expect(request.headerFields[.authorization] == "Bearer secret.key")
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "secret.key")
    #expect(
      request.headerFields[HTTPField.Name("X-Client-Info")!]?.hasPrefix("auth-swift/") == true)
  }

  @Test(arguments: [
    (Duration.zero, "none"),
    (.seconds(86_400), "86400s"),
    (.milliseconds(1_500), "1500000000ns"),
    (.seconds(-5), "-5s"),
    (.seconds(Int64.max), "\(Int64.max)ns"),
    (Duration(secondsComponent: 0, attosecondsComponent: 500_000_000), "1ns"),
  ])
  func banDurationIsAGoDurationString(duration: Duration, expected: String) throws {
    let body = try AuthClient.Configuration.jsonEncoder.encode(
      AdminUserAttributes(banDuration: duration))
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["ban_duration"] as? String == expected)
  }

  @Test
  func encodeSendsEveryAttribute() throws {
    let attributes = AdminUserAttributes(
      appMetadata: [:], banDuration: .seconds(1), email: "e", confirmsEmail: true, id: UUID(),
      nonce: "n", password: "p", passwordHash: "h", phone: "1", confirmsPhone: true, role: "r",
      userMetadata: [:])
    let body = try AuthClient.Configuration.jsonEncoder.encode(attributes)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?.count == Mirror(reflecting: attributes).children.count)
  }

  @Test
  func unsetAttributesAreLeftOut() throws {
    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    let body = try AuthClient.Configuration.jsonEncoder.encode(
      AdminUserAttributes(confirmsEmail: true, id: id))
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?.keys.sorted() == ["email_confirm", "id"])
    #expect(json?["id"] as? String == id.uuidString)
  }
}
