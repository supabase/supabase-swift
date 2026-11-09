//
//  AuthAdminTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 30/09/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthAdminTests {
  @Test
  func sendsTheSecretKeyOnEveryRequest() async throws {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
    let admin = AuthAdminClient.testing(secretKey: "secret.key", http: transport)

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

  @Test
  func sendsCustomHeadersWithTheSecretKey() async throws {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
    let admin = AuthAdminClient(
      configuration: .init(
        url: clientURL,
        secretKey: "secret.key",
        headers: [HTTPField.Name("X-Custom")!: "1"],
        http: .init(transport: transport)
      )
    )

    try await admin.deleteUser(id: UUID())

    let request = try #require(transport.requests.first?.head)
    #expect(request.headerFields[HTTPField.Name("X-Custom")!] == "1")
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "secret.key")
  }

  @Test
  func retriesAGetOnTheConfiguredClock() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .serviceUnavailable), Data())
    }
    let clock = SleepCountingClock()
    let admin = AuthAdminClient(
      configuration: .init(
        url: clientURL, secretKey: "secret.key", http: .init(transport: transport), clock: clock)
    )

    _ = try? await admin.user(id: UUID())

    #expect(transport.requests.count == 3)
    #expect(clock.sleeps.value == 2)
  }

  @Test
  func doesNotRetryWhenRetryIsDisabled() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .serviceUnavailable), Data())
    }
    let admin = AuthAdminClient(
      configuration: .init(
        url: clientURL, secretKey: "secret.key", http: .init(transport: transport),
        retryEnabled: false)
    )

    _ = try? await admin.user(id: UUID())

    #expect(transport.requests.count == 1)
  }

  @Test
  func describingTheConfigurationHidesTheSecretKey() {
    let configuration = AuthAdminClient.Configuration(
      url: clientURL, secretKey: "sb_secret_abc",
      headers: [HTTPField.Name("apikey")!: "sb_secret_abc"])
    var dumped = ""
    dump(configuration, to: &dumped)

    #expect(!String(describing: configuration).contains("sb_secret_abc"))
    #expect(!String(reflecting: configuration).contains("sb_secret_abc"))
    #expect(!dumped.contains("sb_secret_abc"))
    #expect(String(describing: configuration).contains("<redacted>"))
  }

  @Test
  func exposesTheConfigurationItWasCreatedWith() {
    let admin = AuthAdminClient(configuration: .init(url: clientURL, secretKey: "secret.key"))

    #expect(admin.configuration.url == clientURL)
    #expect(admin.configuration.secretKey == "secret.key")
    #expect(admin.configuration.headers.isEmpty)
  }

  @Test
  func logsRequestsWithoutTheQueryOrTheSecretKey() async throws {
    let recorder = LogRecorder()
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data("[]".utf8)) }
    let admin = AuthAdminClient(
      configuration: .init(
        url: clientURL,
        secretKey: "sb_secret_admin-key",
        http: .init(transport: transport),
        logger: recorder.makeLogger()
      )
    )

    _ = try? await admin.listUsers(page: 2, pageSize: 5)

    let logged = recorder.entries.joined(separator: "\n")
    #expect(logged.contains("/auth/v1/admin/users"))
    #expect(!logged.contains("page=2"))
    #expect(!logged.contains("sb_secret_admin-key"))
  }

  @Test
  func neverSendsANewFormatSecretKeyAsBearer() async throws {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
    let admin = AuthAdminClient.testing(secretKey: "sb_secret_abc", http: transport)

    try await admin.deleteUser(id: UUID())

    let request = try #require(transport.requests.first?.head)
    #expect(request.headerFields[.authorization] == nil)
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "sb_secret_abc")
  }

  @Test(arguments: [
    (Duration.zero, "none"),
    (.seconds(86_400), "86400s"),
    (.milliseconds(1_500), "1500000000ns"),
    (.seconds(-5), "-5s"),
    (.seconds(Int64.max), "\(Int64.max)ns"),
    (Duration(secondsComponent: 0, attosecondsComponent: 500_000_000), "1ns"),
    (Duration(secondsComponent: Int64.min, attosecondsComponent: -1), "\(Int64.min)ns"),
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

/// Sleeps at once and counts the sleeps, so a test can see which clock a retry waited on.
private struct SleepCountingClock: Clock {
  let base = ImmediateClock()
  let sleeps = LockIsolated(0)

  var now: ImmediateClock<Duration>.Instant { base.now }
  var minimumResolution: Duration { base.minimumResolution }

  func sleep(until deadline: ImmediateClock<Duration>.Instant, tolerance: Duration?) async throws {
    sleeps.withValue { $0 += 1 }
    try await base.sleep(until: deadline, tolerance: tolerance)
  }
}
