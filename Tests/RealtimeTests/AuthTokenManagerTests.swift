//
//  AuthTokenManagerTests.swift
//  Realtime Tests
//
//  Created on 17/01/25.
//

import ConcurrencyExtras
import Foundation
import XCTest

@testable import Realtime

final class AuthTokenManagerTests: XCTestCase {
  var manager: AuthTokenManager!

  override func tearDown() async throws {
    manager = nil
    try await super.tearDown()
  }

  // MARK: - Tests

  func testInitWithToken() async {
    manager = AuthTokenManager(initialToken: "initial-token", tokenProvider: nil)

    let token = await manager.getCurrentToken()

    XCTAssertEqual(token, "initial-token")
  }

  func testInitWithoutToken() async {
    manager = AuthTokenManager(initialToken: nil, tokenProvider: nil)

    let token = await manager.getCurrentToken()

    XCTAssertNil(token)
  }

  func testGetCurrentTokenCallsProviderWhenNoToken() async {
    let providerCallCount = LockIsolated(0)

    manager = AuthTokenManager(
      initialToken: nil,
      tokenProvider: {
        providerCallCount.withValue { $0 += 1 }
        return "provider-token"
      }
    )

    let token = await manager.getCurrentToken()

    XCTAssertEqual(token, "provider-token")
    XCTAssertEqual(providerCallCount.value, 1)

    // Second call should use cached token, not call provider again
    let token2 = await manager.getCurrentToken()

    XCTAssertEqual(token2, "provider-token")
    XCTAssertEqual(providerCallCount.value, 1, "Should not call provider again")
  }

  func testGetCurrentTokenReturnsInitialTokenWithoutCallingProvider() async {
    let providerCallCount = LockIsolated(0)

    manager = AuthTokenManager(
      initialToken: "initial-token",
      tokenProvider: {
        providerCallCount.withValue { $0 += 1 }
        return "provider-token"
      }
    )

    let token = await manager.getCurrentToken()

    XCTAssertEqual(token, "initial-token")
    XCTAssertEqual(providerCallCount.value, 0, "Should not call provider when token exists")
  }

  func testUpdateTokenReturnsTrueWhenChanged() async {
    manager = AuthTokenManager(initialToken: "old-token", tokenProvider: nil)

    let changed = await manager.updateToken("new-token")

    XCTAssertTrue(changed)

    let token = await manager.getCurrentToken()
    XCTAssertEqual(token, "new-token")
  }

  func testUpdateTokenReturnsFalseWhenSame() async {
    manager = AuthTokenManager(initialToken: "same-token", tokenProvider: nil)

    let changed = await manager.updateToken("same-token")

    XCTAssertFalse(changed)
  }

  func testUpdateTokenToNil() async {
    manager = AuthTokenManager(initialToken: "some-token", tokenProvider: nil)

    let changed = await manager.updateToken(nil)

    XCTAssertTrue(changed)

    let token = await manager.token
    XCTAssertNil(token)
  }

  func testRefreshTokenCallsProvider() async {
    let providerCallCount = LockIsolated(0)

    manager = AuthTokenManager(
      initialToken: "initial-token",
      tokenProvider: {
        providerCallCount.withValue {
          $0 += 1
          return "refreshed-token-\($0)"
        }
      }
    )

    let token1 = await manager.refreshToken()

    XCTAssertEqual(token1, "refreshed-token-1")
    XCTAssertEqual(providerCallCount.value, 1)

    // Refresh again
    let token2 = await manager.refreshToken()

    XCTAssertEqual(token2, "refreshed-token-2")
    XCTAssertEqual(providerCallCount.value, 2)
  }

  func testRefreshTokenWithoutProviderReturnsCurrentToken() async {
    manager = AuthTokenManager(initialToken: "current-token", tokenProvider: nil)

    let token = await manager.refreshToken()

    XCTAssertEqual(token, "current-token")
  }

  func testRefreshTokenUpdatesInternalToken() async {
    manager = AuthTokenManager(
      initialToken: "old-token",
      tokenProvider: { "new-token" }
    )

    _ = await manager.refreshToken()

    let token = await manager.token
    XCTAssertEqual(token, "new-token")
  }

  func testProviderThrowingError() async {
    manager = AuthTokenManager(
      initialToken: nil,
      tokenProvider: {
        throw NSError(domain: "test", code: 1)
      }
    )

    let token = await manager.getCurrentToken()

    XCTAssertNil(token, "Should return nil when provider throws")
  }

  func testConcurrentAccess() async {
    manager = AuthTokenManager(initialToken: "initial", tokenProvider: nil)

    // Concurrent updates
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          _ = await self.manager.updateToken("token-\(i)")
        }
      }

      await group.waitForAll()
    }

    // Should have some token (race condition, but should not crash)
    let token = await manager.token
    XCTAssertNotNil(token)
    XCTAssertTrue(token!.starts(with: "token-"))
  }

  func testTokenPropertyReturnsCurrentValue() async {
    manager = AuthTokenManager(initialToken: "test-token", tokenProvider: nil)

    let token = await manager.token

    XCTAssertEqual(token, "test-token")
  }
}
