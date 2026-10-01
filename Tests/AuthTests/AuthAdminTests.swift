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
  func standaloneAdminNeedsNoClient() async throws {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
    let admin = AuthAdmin(
      url: URL(string: "http://localhost:54321/auth/v1")!,
      headers: ["apikey": "secret.key", "Authorization": "Bearer secret.key"],
      http: .init(transport: transport)
    )

    let id = UUID()
    try await admin.deleteUser(id: id)

    let request = try #require(transport.requests.first?.head)
    #expect(request.method == .delete)
    #expect(request.url?.path == "/auth/v1/admin/users/\(id)")
    #expect(request.headerFields[.authorization] == "Bearer secret.key")
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "secret.key")
  }
}
