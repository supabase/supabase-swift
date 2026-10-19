//
//  PushHandle.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import ConcurrencyExtras
import Foundation

/// The server's reply status to a push, or ``timeout`` when no reply arrived in time.
///
/// A reply status this SDK has no member for is preserved in ``rawValue``.
public struct PushStatus: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``PushStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``PushStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The server acknowledged the push.
  public static let ok: PushStatus = "ok"

  /// The server rejected the push.
  public static let error: PushStatus = "error"

  /// No reply arrived within the configured timeout interval.
  public static let timeout: PushStatus = "timeout"
}

/// A handle to a message pushed over the WebSocket, for callers that want to await, cancel, or
/// inspect the server's reply.
///
/// ``RealtimeChannel/broadcast(event:message:)`` and the other push methods return one. Ignore
/// it for fire-and-forget delivery, or call it to wait for the reply:
///
/// ```swift
/// let push = await channel.broadcast(event: "cursor", message: ["x": 1])
/// let status = try await push()   // `.ok`, or `.timeout` when no reply came in time
/// ```
///
/// A push that the server rejects, or that is dropped because the channel left or the socket
/// closed, fails: ``error`` is set and awaiting the handle throws it.
///
/// ## Topics
/// ### Observing the push
/// - ``isRunning``
/// - ``error``
/// ### Waiting and cancelling
/// - ``callAsFunction()``
/// - ``cancel()``
public struct PushHandle: Sendable {
  private enum Outcome {
    case status(PushStatus)
    case failure(any Error)
    case cancelled
  }

  private struct State {
    var outcome: Outcome?
    var waiters: [UUID: CheckedContinuation<PushStatus, any Error>] = [:]
  }

  private let state = LockIsolated(State())

  init() {}

  /// A handle whose reply is already known, for pushes that need no acknowledgement.
  static func resolved(_ status: PushStatus) -> PushHandle {
    let handle = PushHandle()
    handle.resolve(status)
    return handle
  }

  /// A handle for a push that could not be sent.
  static func failed(_ error: any Error) -> PushHandle {
    let handle = PushHandle()
    handle.fail(error)
    return handle
  }

  /// `true` until the reply arrives, the push times out or fails, or ``cancel()`` is called.
  public var isRunning: Bool {
    state.value.outcome == nil
  }

  /// The error the push failed with, or `nil` while it is running, after a reply, and after
  /// ``cancel()``.
  public var error: (any Error)? {
    if case .failure(let error)? = state.value.outcome {
      return error
    }
    return nil
  }

  /// Stops waiting for the reply.
  ///
  /// ``isRunning`` becomes `false`, ``error`` stays `nil`, and every caller awaiting the handle
  /// gets a `CancellationError`. The frame itself has already been sent and is not recalled.
  public func cancel() {
    settle(.cancelled)
  }

  /// Waits for the server's reply.
  ///
  /// - Returns: ``PushStatus/ok`` when the server acknowledged the push, or
  ///   ``PushStatus/timeout`` when no reply arrived within the client's configured timeout.
  /// - Throws: ``RealtimeError`` when the server rejected the push or the channel could not
  ///   deliver it, and `CancellationError` after ``cancel()`` or when the awaiting task is
  ///   cancelled.
  public func callAsFunction() async throws -> PushStatus {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let settled: Outcome? = state.withValue { state in
          if let outcome = state.outcome {
            return outcome
          }
          // `onCancel` may already have run, before this waiter existed; registering now would
          // wait forever, so answer the cancellation here instead.
          if Task.isCancelled {
            return .cancelled
          }
          state.waiters[id] = continuation
          return nil
        }
        if let settled {
          Self.resume(continuation, with: settled)
        }
      }
    } onCancel: {
      let waiter = state.withValue { $0.waiters.removeValue(forKey: id) }
      waiter?.resume(throwing: CancellationError())
    }
  }

  func resolve(_ status: PushStatus) {
    settle(.status(status))
  }

  func fail(_ error: any Error) {
    settle(.failure(error))
  }

  /// Records the first outcome and wakes every waiter. Later outcomes are ignored.
  ///
  /// Waiters are snapshotted under the lock and resumed outside of it; see `StatusMirror`.
  private func settle(_ outcome: Outcome) {
    let waiters = state.withValue { state -> [CheckedContinuation<PushStatus, any Error>] in
      guard state.outcome == nil else { return [] }
      state.outcome = outcome
      defer { state.waiters.removeAll() }
      return Array(state.waiters.values)
    }
    for waiter in waiters {
      Self.resume(waiter, with: outcome)
    }
  }

  private static func resume(
    _ continuation: CheckedContinuation<PushStatus, any Error>, with outcome: Outcome
  ) {
    switch outcome {
    case .status(let status): continuation.resume(returning: status)
    case .failure(let error): continuation.resume(throwing: error)
    case .cancelled: continuation.resume(throwing: CancellationError())
    }
  }
}
