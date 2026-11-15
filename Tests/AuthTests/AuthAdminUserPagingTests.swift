//
//  AuthAdminUserPagingTests.swift
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
struct AuthAdminUserPagingTests {
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

  private func link(next: Int?, last: Int) -> String {
    let lastLink = "</admin/users?page=\(last)&per_page=>; rel=\"last\""
    guard let next else { return lastLink }
    return "</admin/users?page=\(next)&per_page=>; rel=\"next\", " + lastLink
  }

  private func makeSUT(
    pages: [(emails: [String], next: Int?)]
  ) -> (AuthAdminClient, RecordingTransport) {
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

    return (.testing(http: transport), transport)
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
    for try await user in sut.users() {
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

    for try await _ in sut.users(pageSize: 1) {}

    let pageParams = transport.requests.map { request in
      URLComponents(string: request.head.url?.absoluteString ?? "")?
        .queryItems?
        .filter { $0.name == "page" || $0.name == "per_page" }
        .map { "\($0.name)=\($0.value ?? "")" }
        .joined(separator: "&") ?? ""
    }

    expectNoDifference(pageParams, ["per_page=1", "page=2&per_page=1", "page=3&per_page=1"])
  }

  @Test
  func usersStopsAtASinglePage() async throws {
    let (sut, transport) = makeSUT(pages: [(["only@example.com"], nil)])

    var emails: [String] = []
    for try await user in sut.users() {
      emails.append(user.email ?? "")
    }

    expectNoDifference(emails, ["only@example.com"])
    expectNoDifference(transport.requests.count, 1)
  }

  @Test
  func usersFetchesPagesLazily() async throws {
    let (sut, transport) = makeSUT(
      pages: [
        (["a@example.com", "b@example.com"], 2),
        (["c@example.com"], nil),
      ]
    )

    for try await user in sut.users() where user.email == "a@example.com" {
      break
    }

    expectNoDifference(transport.requests.count, 1)
  }

  @Test
  func usersYieldsNothingWhenTheOnlyPageIsEmpty() async throws {
    let (sut, transport) = makeSUT(pages: [([], nil)])

    var count = 0
    for try await _ in sut.users() { count += 1 }

    expectNoDifference(count, 0)
    expectNoDifference(transport.requests.count, 1)
  }

  @Test
  func usersPagesYieldsEachUserPage() async throws {
    let (sut, transport) = makeSUT(
      pages: [(["a@example.com", "b@example.com"], 2), (["c@example.com"], nil)]
    )

    let pages = try await sut.users(pageSize: 2).pages.collect()

    expectNoDifference(
      pages.map { $0.users.map(\.email) }, [["a@example.com", "b@example.com"], ["c@example.com"]])
    expectNoDifference(pages.map(\.nextPage), [2, nil])
    expectNoDifference(pages.map(\.total), [3, 3])
    expectNoDifference(transport.requests.count, 2)
  }

  @Test
  func usersPageAfterFetchesThatPageNumber() async throws {
    let (sut, transport) = makeSUT(pages: [(["c@example.com"], nil)])

    let page = try await sut.users(pageSize: 1).page(after: 3)

    expectNoDifference(page.users.map(\.email), ["c@example.com"])
    let query = URLComponents(string: transport.requests.first?.head.url?.absoluteString ?? "")?
      .queryItems?.filter { $0.name == "page" || $0.name == "per_page" }
    expectNoDifference(
      query, [URLQueryItem(name: "page", value: "3"), URLQueryItem(name: "per_page", value: "1")])
  }

  @Test
  func usersPropagatesTransportFailures() async throws {
    struct Boom: Error {}

    let transport = RecordingTransport { _, _ in throw Boom() }
    let sut = AuthAdminClient.testing(http: transport)

    await #expect(throws: Boom.self) {
      for try await _ in sut.users() {}
    }
  }
}
