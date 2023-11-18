//
//  GoTrueClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras

@testable import GoTrue

final class GoTrueClientTests: XCTestCase {
  fileprivate var api: APIClient!

  func testAuthStateChanges() async throws {
    let session = Session.validSession
    let sut = makeSUT()

    let events = ActorIsolated([AuthChangeEvent]())
    let expectation = expectation(description: "onAuthStateChangeEnd")

    await withDependencies {
      $0.eventEmitter = .live
      $0.sessionManager.session = { @Sendable _ in session }
    } operation: {
      let authStateStream = await sut.authStateChanges

      let streamTask = Task {
        for await (event, _) in authStateStream {
          await events.withValue {
            $0.append(event)
          }

          expectation.fulfill()
        }
      }

      await fulfillment(of: [expectation])

      let events = await events.value
      XCTAssertEqual(events, [.initialSession])

      streamTask.cancel()
    }
  }

  private func makeSUT(fetch: GoTrueClient.FetchHandler? = nil) -> GoTrueClient {
    let configuration = GoTrueClient.Configuration(
      url: clientURL,
      headers: ["apikey": "dummy.api.key"],
      fetch: { request in
        if let fetch {
          return try await fetch(request)
        }

        throw UnimplementedError()
      }
    )

    api = APIClient(http: HTTPClient(fetchHandler: configuration.fetch))

    let sut = GoTrueClient(
      configuration: configuration,
      sessionManager: .mock,
      codeVerifierStorage: .mock,
      api: api,
      eventEmitter: .mock,
      sessionStorage: .mock
    )

    addTeardownBlock { [weak sut] in
      XCTAssertNil(sut, "sut should be deallocated.")
    }

    return sut
  }
}
