//
//  AuthAdminUserSequenceTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 16/09/26.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthAdminUserSequenceTests {
  /// Builds a `GET /admin/users` body holding one user per element of `emails`.
  private func page(_ emails: [String]) -> Data {
    let users = emails.map { email in
      """
      {
        "id": "\(UUID().uuidString.lowercased())",
        "aud": "authenticated",
        "role": "authenticated",
        "email": "\(email)",
        "phone": "",
        "app_metadata": {},
        "user_metadata": {},
        "created_at": "2024-09-23T10:55:18.375179Z",
        "updated_at": "2024-09-23T10:55:18.385003Z"
      }
      """
    }
    return Data(#"{"users": [\#(users.joined(separator: ","))], "aud": "authenticated"}"#.utf8)
  }

  /// A `Link` header advertising `next` (when non-nil) and `last`, the way GoTrue sends it.
  private func link(next: Int?, last: Int) -> String {
    let lastLink = "</admin/users?page=\(last)&per_page=>; rel=\"last\""
    guard let next else { return lastLink }
    return "</admin/users?page=\(next)&per_page=>; rel=\"next\", " + lastLink
  }

  /// A client whose `admin/users` endpoint serves `pages` in order, one per request.
  ///
  /// Returns the client and the transport, so a test can assert on how many requests the
  /// sequence actually issued.
  private func makeSUT(pages: [(emails: [String], next: Int?)]) -> (AuthClient, RecordingTransport)
  {
    let served = LockIsolated(0)
    let transport = RecordingTransport { _, _ in
      let index = served.withValue { value -> Int in
        defer { value += 1 }
        return value
      }
      let page = pages[index]
      let response = HTTPResponse(
        status: .ok,
        headerFields: [
          .init("X-Total-Count")!: "\(pages.reduce(0) { $0 + $1.emails.count })",
          .init("Link")!: self.link(next: page.next, last: pages.count),
        ]
      )
      return (response, self.page(page.emails))
    }

    let client = AuthClient(
      configuration: AuthClient.Configuration(
        url: clientURL,
        headers: ["apikey": "supabase.publishable.key"],
        localStorage: InMemoryLocalStorage(),
        http: .init(transport: transport)
      )
    )
    return (client, transport)
  }

  @Test
  func usersYieldsEveryPageInOrder() async throws {
    let (sut, transport) = makeSUT(
      pages: [
        (["a@example.com", "b@example.com"], 2),
        (["c@example.com"], 3),
        (["d@example.com"], nil),
      ]
    )

    var emails: [String] = []
    for try await user in sut.admin.users() {
      emails.append(user.email ?? "")
    }

    expectNoDifference(
      emails, ["a@example.com", "b@example.com", "c@example.com", "d@example.com"])
    expectNoDifference(transport.requests.count, 3)
  }

  @Test
  func usersRequestsEachPageInTurn() async throws {
    let (sut, transport) = makeSUT(
      pages: [(["a@example.com"], 2), (["b@example.com"], 3), (["c@example.com"], nil)]
    )

    for try await _ in sut.admin.users(perPage: 1) {}

    let pageParams = transport.requests.map { request in
      URLComponents(string: request.head.url?.absoluteString ?? "")?
        .queryItems?
        .filter { $0.name == "page" || $0.name == "per_page" }
        .map { "\($0.name)=\($0.value ?? "")" }
        .joined(separator: "&") ?? ""
    }

    expectNoDifference(pageParams, ["page=&per_page=1", "page=2&per_page=1", "page=3&per_page=1"])
  }

  @Test
  func usersStopsAtASinglePage() async throws {
    let (sut, transport) = makeSUT(pages: [(["only@example.com"], nil)])

    var emails: [String] = []
    for try await user in sut.admin.users() {
      emails.append(user.email ?? "")
    }

    expectNoDifference(emails, ["only@example.com"])
    expectNoDifference(transport.requests.count, 1)
  }

  /// The reason this is an `AsyncSequence` and not an `AsyncThrowingStream`: a caller that stops
  /// early must not have paid for the pages it never read.
  @Test
  func usersFetchesPagesLazily() async throws {
    let (sut, transport) = makeSUT(
      pages: [
        (["a@example.com", "b@example.com"], 2),
        (["c@example.com"], nil),
      ]
    )

    for try await user in sut.admin.users() where user.email == "a@example.com" {
      break
    }

    expectNoDifference(transport.requests.count, 1)
  }

  @Test
  func usersYieldsNothingWhenTheOnlyPageIsEmpty() async throws {
    let (sut, transport) = makeSUT(pages: [([], nil)])

    var count = 0
    for try await _ in sut.admin.users() { count += 1 }

    expectNoDifference(count, 0)
    expectNoDifference(transport.requests.count, 1)
  }

  @Test
  func usersPropagatesTransportFailures() async throws {
    struct Boom: Error {}

    let transport = RecordingTransport { _, _ in throw Boom() }
    let sut = AuthClient(
      configuration: AuthClient.Configuration(
        url: clientURL,
        localStorage: InMemoryLocalStorage(),
        http: .init(transport: transport)
      )
    )

    await #expect(throws: Boom.self) {
      for try await _ in sut.admin.users() {}
    }
  }
}
