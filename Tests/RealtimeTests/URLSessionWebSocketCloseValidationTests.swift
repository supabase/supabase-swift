//
//  URLSessionWebSocketCloseValidationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/26.
//

import Foundation
import Testing

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct URLSessionWebSocketCloseValidationTests {
  @Test(arguments: [1000, 1001, 1002, 1003, 1007, 1011, 3000, 4000, 4999])
  func acceptsCloseCodesRFC6455Allows(code: Int) {
    #expect(URLSessionWebSocketTransport.validatedCloseCode(code) == code)
  }

  @Test
  func passesNoCodeThrough() {
    #expect(URLSessionWebSocketTransport.validatedCloseCode(nil) == nil)
  }

  @Test(arguments: [1004, 1005, 1006, 1015, 2999, 5000, 0, -1])
  func dropsCloseCodesRFC6455Forbids(code: Int) {
    #expect(URLSessionWebSocketTransport.validatedCloseCode(code) == nil)
  }

  @Test
  func passesReasonWithinTheByteLimitThrough() {
    let reason = String(repeating: "a", count: 123)
    #expect(URLSessionWebSocketTransport.validatedCloseReason(reason) == reason)
    #expect(URLSessionWebSocketTransport.validatedCloseReason(nil) == nil)
  }

  @Test
  func truncatesAnOverlongReasonToAPrefix() throws {
    let reason = String(repeating: "a", count: 200)
    let truncated = URLSessionWebSocketTransport.validatedCloseReason(reason)

    #expect(truncated == String(repeating: "a", count: 123))
    #expect(reason.hasPrefix(try #require(truncated)))
  }

  @Test
  func truncatesOnWholeCharactersSoTheFrameNeverSplitsAScalar() throws {
    let reason = String(repeating: "🚀", count: 40)
    let truncated = URLSessionWebSocketTransport.validatedCloseReason(reason)

    #expect(truncated == String(repeating: "🚀", count: 30))
    #expect(try #require(truncated).utf8.count <= 123)
    #expect(reason.hasPrefix(try #require(truncated)))
  }

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
  /// cases, so 3000...4999 convert to `nil`. `URLSessionWebSocketConnection.close(code:reason:)` closes
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
  func reportsNoCloseFrameForASocketThatIsAlreadyDisconnected() {
    let error = NSError(
      domain: NSPOSIXErrorDomain,
      code: Int(ENOTCONN),
      userInfo: nil
    )

    #expect(URLSessionWebSocketTransport.closeFrame(for: error) == nil)
  }

  @Test
  func treatsTheENOTCONNCodeInAnotherDomainAsAnOrdinaryError() throws {
    let error = NSError(
      domain: NSURLErrorDomain,
      code: Int(ENOTCONN),
      userInfo: nil
    )
    let frame = try #require(URLSessionWebSocketTransport.closeFrame(for: error))

    #expect(frame.code == 1006)
    #expect(frame.reason == error.localizedDescription)
  }

  @Test
  func mapsAProtocolErrorToProtocolError() throws {
    let error = NSError(
      domain: NSPOSIXErrorDomain,
      code: Int(EPROTO),
      userInfo: nil
    )
    let frame = try #require(URLSessionWebSocketTransport.closeFrame(for: error))

    #expect(frame.code == 1002)
    #expect(frame.reason == error.localizedDescription)
  }

  @Test(
    arguments: [
      (NSURLErrorTimedOut, "Connection timed out"),
      (NSURLErrorNetworkConnectionLost, "Network connection lost"),
      (NSURLErrorNotConnectedToInternet, "No internet connection"),
    ]
  )
  func mapsKnownURLErrorsToAbnormalClosureWithAFixedReason(code: Int, reason: String) throws {
    let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: nil)
    let frame = try #require(URLSessionWebSocketTransport.closeFrame(for: error))

    #expect(frame.code == 1006)
    #expect(frame.reason == reason)
  }

  @Test
  func mapsAnUnrecognizedErrorToAbnormalClosure() throws {
    let error = NSError(domain: NSCocoaErrorDomain, code: 42, userInfo: nil)
    let frame = try #require(URLSessionWebSocketTransport.closeFrame(for: error))

    #expect(frame.code == 1006)
    #expect(frame.reason == error.localizedDescription)
  }

  @Test
  func mapsANativeSwiftErrorToAbnormalClosure() throws {
    let error = RealtimeError.decoding("Received unsupported message type")
    let frame = try #require(URLSessionWebSocketTransport.closeFrame(for: error))

    #expect(frame.code == 1006)
    #expect(frame.reason == (error as NSError).localizedDescription)
  }
}
