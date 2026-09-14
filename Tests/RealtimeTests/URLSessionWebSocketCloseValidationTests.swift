//
//  URLSessionWebSocketCloseValidationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/26.
//

import Foundation
import Testing

@testable import RealtimeV2

#if canImport(FoundationNetworking)
  // `URLSessionWebSocketTask` lives in `FoundationNetworking` on Linux, matching the guard in
  // `URLSessionWebSocket.swift`.
  import FoundationNetworking
#endif

/// `close(code:reason:)` takes both values straight from user code, so neither may trap.
///
/// The validators are pure — `close` reports the rejection — so these tests never drive
/// `reportIssue`, which segfaults under `xcodebuild test` (SDK-435).
@Suite
struct URLSessionWebSocketCloseValidationTests {
  @Test(arguments: [1000, 3000, 4000, 4999])
  func acceptsCloseCodesRFC6455Allows(code: Int) {
    #expect(URLSessionWebSocket.validatedCloseCode(code) == code)
  }

  @Test
  func passesNoCodeThrough() {
    #expect(URLSessionWebSocket.validatedCloseCode(nil) == nil)
  }

  @Test(arguments: [1001, 1005, 1006, 2999, 5000, 0, -1])
  func dropsCloseCodesRFC6455Forbids(code: Int) {
    // Dropping the code closes without one (the peer sees 1005) rather than trapping.
    #expect(URLSessionWebSocket.validatedCloseCode(code) == nil)
  }

  @Test
  func passesReasonWithinTheByteLimitThrough() {
    let reason = String(repeating: "a", count: 123)
    #expect(URLSessionWebSocket.validatedCloseReason(reason) == reason)
    #expect(URLSessionWebSocket.validatedCloseReason(nil) == nil)
  }

  @Test
  func truncatesAnOverlongReasonToAPrefix() throws {
    let reason = String(repeating: "a", count: 200)
    let truncated = URLSessionWebSocket.validatedCloseReason(reason)

    #expect(truncated == String(repeating: "a", count: 123))
    #expect(reason.hasPrefix(try #require(truncated)))
  }

  @Test
  func truncatesOnWholeCharactersSoTheFrameNeverSplitsAScalar() throws {
    // Each rocket is 4 UTF-8 bytes, so 30 fit within the 123-byte limit (120) and the 31st
    // would overshoot it at 124. A byte-wise cut would split that 31st rocket, leaving a
    // replacement character — the result would be neither this value nor a prefix of the original.
    let reason = String(repeating: "🚀", count: 40)
    let truncated = URLSessionWebSocket.validatedCloseReason(reason)

    #expect(truncated == String(repeating: "🚀", count: 30))
    #expect(try #require(truncated).utf8.count <= 123)
    #expect(reason.hasPrefix(try #require(truncated)))
  }

  /// 1000 is a named case everywhere, so it converts on every platform.
  @Test
  func normalClosureConvertsOnEveryPlatform() throws {
    let converted = try #require(URLSessionWebSocketTask.CloseCode(rawValue: 1000))
    #expect(converted.rawValue == 1000)
  }

  /// The application range RFC 6455 §7.4 permits is only actually *sendable* where
  /// `URLSessionWebSocketTask.CloseCode` can represent it, and the platforms disagree.
  ///
  /// On Darwin `CloseCode` comes from Objective-C as a non-exhaustive `NS_ENUM`, so any `Int`
  /// round-trips. In swift-corelibs-foundation it is a plain Swift enum with only the named
  /// cases, so 3000...4999 convert to `nil`. ``URLSessionWebSocket/close(code:reason:)`` closes
  /// without a status in that case instead of substituting a different code.
  ///
  /// Pinned because assuming the Darwin result held everywhere was wrong.
  @Test(arguments: [3000, 4000, 4001, 4999])
  func applicationCloseCodesConvertOnlyWhereThePlatformRepresentsThem(code: Int) {
    let converted = URLSessionWebSocketTask.CloseCode(rawValue: code)

    #if canImport(FoundationNetworking)
      #expect(converted == nil)
    #else
      #expect(converted?.rawValue == code)
    #endif
  }

  @Test
  func rejectsANonWebSocketSchemeInsteadOfTrapping() async {
    await #expect(throws: WebSocketError.self) {
      _ = try await URLSessionWebSocket.connect(to: URL(string: "https://example.com")!)
    }
  }
}
