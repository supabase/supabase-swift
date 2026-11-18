//
//  URLSession+WebSocketDelegate.swift
//  Realtime
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension URLSession {
  /// Creates a URLSession with WebSocket delegate callbacks.
  ///
  /// This factory method creates a URLSession configured with the specified delegate callbacks
  /// for handling WebSocket lifecycle events. The session uses a dedicated operation queue
  /// with maximum concurrency of 1 to ensure proper sequencing of delegate callbacks.
  ///
  /// - Parameters:
  ///   - configuration: The URLSession configuration to use.
  ///   - onComplete: Optional callback when a task completes (with or without error).
  ///   - onWebSocketTaskOpened: Optional callback when a WebSocket connection opens successfully.
  ///   - onWebSocketTaskClosed: Optional callback when a WebSocket connection closes.
  ///   - wrappedDelegate: An optional delegate that receives the auth challenges.
  ///   - wrappedDelegateQueue: The queue `wrappedDelegate` is called on. `nil` calls it on the
  ///     session's own serial queue.
  /// - Returns: A configured URLSession instance.
  static func sessionWithConfiguration(
    _ configuration: URLSessionConfiguration,
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)? = nil,
    onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)? =
      nil,
    onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)? =
      nil,
    wrappedDelegate: (any URLSessionDelegate)? = nil,
    wrappedDelegateQueue: OperationQueue? = nil
  ) -> URLSession {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1

    let hasDelegate =
      onComplete != nil || onWebSocketTaskOpened != nil || onWebSocketTaskClosed != nil
      || wrappedDelegate != nil

    if hasDelegate {
      return URLSession(
        configuration: configuration,
        delegate: _Delegate(
          onComplete: onComplete,
          onWebSocketTaskOpened: onWebSocketTaskOpened,
          onWebSocketTaskClosed: onWebSocketTaskClosed,
          wrappedDelegate: wrappedDelegate,
          wrappedDelegateQueue: wrappedDelegateQueue
        ),
        delegateQueue: queue
      )
    } else {
      return URLSession(configuration: configuration)
    }
  }
}

/// Internal URLSession delegate for handling WebSocket events.
///
/// This delegate handles the various WebSocket lifecycle events and forwards them
/// to the appropriate callbacks provided during URLSession creation. It also forwards
/// TLS/auth-challenge callbacks to a wrapped delegate (typically the caller's own
/// session delegate), so apps can pin certificates on the Realtime WebSocket connection
/// using the same `URLSessionDelegate` they already use elsewhere.
final class _Delegate: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate,
  URLSessionWebSocketDelegate
{
  /// Callback for task completion events.
  let onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?
  /// Callback for WebSocket connection opened events.
  let onWebSocketTaskOpened: (@Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void)?
  /// Callback for WebSocket connection closed events.
  let onWebSocketTaskClosed: (@Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void)?
  /// The delegate captured from the caller's own `URLSession` (if any), consulted for
  /// auth-challenge forwarding only. Read-only after `init`; only ever invoked from the
  /// URLSession delegate queue, the same way `URLSession` itself would call it.
  private let wrappedDelegate: (any URLSessionDelegate)?
  /// The queue `wrappedDelegate` expects its calls on: the `delegateQueue` of the session it
  /// came from. A delegate built for `.main` can be main-actor isolated, and calling it from the
  /// session's own queue would trap. `nil` calls it on the session's queue.
  private let wrappedDelegateQueue: OperationQueue?
  /// The task `connect` creates for this connection, set once right after creation (the
  /// delegate must exist before the task can be created, since the session needs a
  /// delegate at construction time). Used to forward auth challenges to `wrappedDelegate`'s
  /// task-level implementation with a real task reference, even though the challenge itself
  /// arrives through this delegate's session-level callback.
  let associatedTask = LockIsolated<URLSessionTask?>(nil)

  init(
    onComplete: (@Sendable (URLSession, URLSessionTask, (any Error)?) -> Void)?,
    onWebSocketTaskOpened: (
      @Sendable (URLSession, URLSessionWebSocketTask, String?) -> Void
    )?,
    onWebSocketTaskClosed: (
      @Sendable (URLSession, URLSessionWebSocketTask, Int?, Data?) -> Void
    )?,
    wrappedDelegate: (any URLSessionDelegate)? = nil,
    wrappedDelegateQueue: OperationQueue? = nil
  ) {
    self.onComplete = onComplete
    self.onWebSocketTaskOpened = onWebSocketTaskOpened
    self.onWebSocketTaskClosed = onWebSocketTaskClosed
    self.wrappedDelegate = wrappedDelegate
    self.wrappedDelegateQueue = wrappedDelegateQueue
  }

  /// Called when a task completes, with or without error.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    onComplete?(session, task, error)
  }

  /// Called when a WebSocket connection is successfully established.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onWebSocketTaskOpened?(session, webSocketTask, `protocol`)
  }

  /// Called when a WebSocket connection is closed.
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onWebSocketTaskClosed?(session, webSocketTask, closeCode.rawValue, reason)
  }

  /// Forwards the auth challenge to `wrappedDelegate`, trying its task-level implementation
  /// first (the modern, recommended form since iOS 15/macOS 12), then falling back to its
  /// session-level implementation, then to default handling. Always calls
  /// `completionHandler` exactly once.
  ///
  /// This delegate is only ever attached at the session level (see `connect`), so the OS
  /// always calls this method — never the task-level overload — even when `wrappedDelegate`
  /// itself only implements the task-level one. `associatedTask` supplies a real task
  /// reference for that forwarding attempt despite this method itself not receiving one.
  ///
  /// The `#selector`/`responds(to:)` checks require the Objective-C runtime, unavailable in
  /// swift-corelibs-foundation (Linux) — guarded accordingly. `wrappedDelegate` may still be
  /// populated on Linux (`connect` doesn't special-case it), but this method ignores it there
  /// and always falls through to default handling: certificate pinning isn't supported on
  /// Linux (build-only, not a production-supported platform for this package).
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) ->
      Void
  ) {
    #if canImport(FoundationNetworking)
      completionHandler(.performDefaultHandling, nil)
    #else
      guard let wrappedDelegate else {
        completionHandler(.performDefaultHandling, nil)
        return
      }
      if let wrappedDelegateQueue, OperationQueue.current !== wrappedDelegateQueue {
        let call = UncheckedSendable((self, session, challenge, wrappedDelegate))
        wrappedDelegateQueue.addOperation {
          let (delegate, session, challenge, wrappedDelegate) = call.value
          delegate.forward(challenge, from: session, to: wrappedDelegate, completionHandler)
        }
        return
      }
      forward(challenge, from: session, to: wrappedDelegate, completionHandler)
    #endif
  }

  #if !canImport(FoundationNetworking)
    private func forward(
      _ challenge: URLAuthenticationChallenge,
      from session: URLSession,
      to wrappedDelegate: any URLSessionDelegate,
      _ completionHandler:
        @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      if let task = associatedTask.value,
        let taskDelegate = wrappedDelegate as? any URLSessionTaskDelegate,
        wrappedDelegate.responds(
          to: #selector(
            (any URLSessionTaskDelegate).urlSession(_:task:didReceive:completionHandler:)))
      {
        taskDelegate.urlSession?(
          session, task: task, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      if wrappedDelegate.responds(
        to: #selector((any URLSessionDelegate).urlSession(_:didReceive:completionHandler:)))
      {
        wrappedDelegate.urlSession?(
          session, didReceive: challenge, completionHandler: completionHandler)
        return
      }

      completionHandler(.performDefaultHandling, nil)
    }
  #endif
}
