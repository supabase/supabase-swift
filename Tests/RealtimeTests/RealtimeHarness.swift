//
//  RealtimeHarness.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import ConcurrencyExtras
import Foundation
import IssueReporting
import Phoenix
import PhoenixTesting

@testable import Realtime

struct RealtimeHarness {
  let clock = ManualClock()
  let transport: FakeTransport
  let client: RealtimeClient

  init(
    replies: ServerReplies = .realtime(),
    configure: (inout RealtimeClientOptions) -> Void = { _ in }
  ) {
    transport = FakeTransport(replies: replies)
    var options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      heartbeatInterval: .seconds(3600),
      handleAppLifecycle: false,
      clock: clock
    )
    configure(&options)
    client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!, options: options,
      transport: transport)
  }

  var socket: Socket { client.connection.socket }

  @discardableResult
  func connect() async throws -> FakeConnection {
    async let connected: Void = client.connect()
    let connection = await transport.nextConnection()
    await connection.open()
    try await connected
    return connection
  }

  func advance(by duration: Duration) async {
    clock.advance(by: duration)
    await socket.settle()
  }

  /// The next connection the socket makes, or `nil` when none comes within `limit` of real time.
  /// `FakeTransport.nextConnection()` ignores cancellation, so a test that awaits it for a
  /// connection that never comes hangs past its time limit.
  func nextConnection(within limit: Duration = .seconds(5)) async -> FakeConnection? {
    let transport = transport
    return await within(limit) { await transport.nextConnection() }
  }

  /// `true` once a sleep waits on the clock, `false` when none does within `limit` of real time.
  /// `ManualClock.waitForSleepers()` ignores cancellation, as `nextConnection()` does.
  func sleeper(within limit: Duration = .seconds(5)) async -> Bool {
    let clock = clock
    return await within(limit) { await clock.waitForSleepers() } != nil
  }
}

private func within<Value: Sendable>(
  _ limit: Duration, _ operation: @escaping @Sendable () async -> Value
) async -> Value? {
  let waiter = LockIsolated<CheckedContinuation<Value?, Never>?>(nil)
  let resume = { @Sendable (value: Value?) in
    waiter.withValue { continuation in
      continuation?.resume(returning: value)
      continuation = nil
    }
  }
  return await withCheckedContinuation { continuation in
    waiter.setValue(continuation)
    Task { resume(await operation()) }
    Task {
      try? await Task.sleep(for: limit)
      resume(nil)
    }
  }
}

extension ServerReplies {
  static func realtime(
    join: @escaping @Sendable (OutboundFrame) -> ServerReply? = { _ in .ok() }
  ) -> ServerReplies {
    ServerReplies { frame in
      switch frame.event {
      case "phx_join": join(frame)
      case "phx_leave", "heartbeat", "presence": .ok()
      default: nil
      }
    }
  }
}

extension FakeConnection {
  func nextSent(_ event: String) async -> OutboundFrame {
    while true {
      let frame = await nextSent()
      if frame.event == event { return frame }
    }
  }

  func nextBinary() async -> Data {
    while true {
      if case .binary(let data) = await nextSentFrame() { return data }
    }
  }

  func serverBroadcast(
    topic: String, joinRef: String?, event: String, payload: Phoenix.JSONValue
  ) async {
    await serverSends(
      topic: Topic(topic), event: "broadcast",
      payload: ["type": "broadcast", "event": .string(event), "payload": payload],
      joinRef: joinRef)
  }
}

func first<Element>(_ count: Int, of stream: AsyncStream<Element>) async -> [Element] {
  var elements: [Element] = []
  guard count > 0 else { return elements }
  for await element in stream {
    elements.append(element)
    if elements.count == count { break }
  }
  return elements
}

func collect<Element>(
  _ stream: AsyncStream<Element>, until isDone: ([Element]) -> Bool
) async -> [Element] {
  var elements: [Element] = []
  for await element in stream {
    elements.append(element)
    if isDone(elements) { break }
  }
  return elements
}

func kind4Frame(
  topic: String, event: String, meta: Data = Data(), encoding: UInt8, payload: Data
) -> Data {
  var frame = Data([
    4, UInt8(Data(topic.utf8).count), UInt8(Data(event.utf8).count), UInt8(meta.count),
    encoding,
  ])
  frame.append(Data(topic.utf8))
  frame.append(Data(event.utf8))
  frame.append(meta)
  frame.append(payload)
  return frame
}

func kind3Refs(_ frame: Data) -> (joinRef: String, ref: String) {
  let bytes = [UInt8](frame)
  let joinRefEnd = 7 + Int(bytes[1])
  let refEnd = joinRefEnd + Int(bytes[2])
  return (
    String(decoding: bytes[7..<joinRefEnd], as: UTF8.self),
    String(decoding: bytes[joinRefEnd..<refEnd], as: UTF8.self)
  )
}

/// `reportIssue` from a `@Test` crashes the process under `xcodebuild test` (SDK-435), so tests
/// that make the SDK report run under `swift test` only, as `HTTPFieldsTests` does.
let runsUnderSwiftTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

/// Collects reported issues, so a test can check that the SDK reported one.
final class IssueCollector: IssueReporter {
  private let messages = LockIsolated<[String]>([])

  var count: Int { messages.value.count }

  func reportIssue(
    _ message: @autoclosure () -> String?,
    severity: IssueSeverity,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {
    let text = message() ?? ""
    messages.withValue { $0.append(text) }
  }

  func reportIssue(
    _ error: any Error,
    _ message: @autoclosure () -> String?,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {
    let text = "\(error)"
    messages.withValue { $0.append(text) }
  }

  func expectIssue(
    _ message: @autoclosure () -> String?,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {}

  func expectIssue(
    _ error: any Error,
    _ message: @autoclosure () -> String?,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {}
}
