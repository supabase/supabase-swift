//
//  LifecycleObserver.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

// MARK: - LifecycleEventSource

/// A source of app lifecycle events (background / foreground) that the `Realtime` actor
/// observes when `Configuration.lifecycle == .automatic`.
///
/// The production implementation wraps platform `NotificationCenter` notifications.
/// Inject a `TestLifecycleEventSource` in tests for deterministic control.
public protocol LifecycleEventSource: Sendable {
  /// Emits a `Void` each time the app enters the background.
  var didEnterBackground: AsyncStream<Void> { get }
  /// Emits a `Void` each time the app is about to enter the foreground.
  var willEnterForeground: AsyncStream<Void> { get }
}

// MARK: - NotificationCenterLifecycleEventSource

#if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)

  /// Production `LifecycleEventSource` backed by `NotificationCenter`.
  ///
  /// - On iOS / tvOS / visionOS: uses `UIApplication.didEnterBackgroundNotification`
  ///   and `UIApplication.willEnterForegroundNotification`.
  /// - On macOS: uses `NSApplication.didResignActiveNotification` and
  ///   `NSApplication.willBecomeActiveNotification`.
  final class NotificationCenterLifecycleEventSource: LifecycleEventSource, @unchecked Sendable {

    let didEnterBackground: AsyncStream<Void>
    let willEnterForeground: AsyncStream<Void>

    private let backgroundContinuation: AsyncStream<Void>.Continuation
    private let foregroundContinuation: AsyncStream<Void>.Continuation
    private var observers: [any NSObjectProtocol] = []

    init() {
      let (bgStream, bgCont) = AsyncStream<Void>.makeStream()
      let (fgStream, fgCont) = AsyncStream<Void>.makeStream()
      self.didEnterBackground = bgStream
      self.willEnterForeground = fgStream
      self.backgroundContinuation = bgCont
      self.foregroundContinuation = fgCont

      let center = NotificationCenter.default

      #if canImport(UIKit)
        let backgroundNotification = UIApplication.didEnterBackgroundNotification
        let foregroundNotification = UIApplication.willEnterForegroundNotification
      #elseif canImport(AppKit)
        let backgroundNotification = NSApplication.didResignActiveNotification
        let foregroundNotification = NSApplication.willBecomeActiveNotification
      #endif

      let bgObserver = center.addObserver(
        forName: backgroundNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.backgroundContinuation.yield(())
      }

      let fgObserver = center.addObserver(
        forName: foregroundNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.foregroundContinuation.yield(())
      }

      observers = [bgObserver, fgObserver]
    }

    deinit {
      let center = NotificationCenter.default
      for observer in observers {
        center.removeObserver(observer)
      }
      backgroundContinuation.finish()
      foregroundContinuation.finish()
    }
  }

#endif

// MARK: - LifecycleObserver (actor-internal helper)

/// Observes a `LifecycleEventSource` and drives reconnect on foreground when the
/// connection was dropped while backgrounded and no intentional disconnect was set.
///
/// Lifecycle:
/// - Created and started when `Realtime` connects (or at init for `.automatic`).
/// - `cancel()` is called on `disconnect()` and on deinit cleanup.
final class LifecycleObserver: Sendable {
  private let task: Task<Void, Never>

  /// Creates the observer and immediately starts listening to `source`.
  ///
  /// - Parameters:
  ///   - source: The `LifecycleEventSource` to observe.
  ///   - client: The `Realtime` actor to callback on foreground.
  init(source: any LifecycleEventSource, client: Realtime) {
    let backgroundStream = source.didEnterBackground
    let foregroundStream = source.willEnterForeground
    self.task = Task { [weak client] in
      await LifecycleObserver._run(
        backgroundStream: backgroundStream,
        foregroundStream: foregroundStream,
        client: client
      )
    }
  }

  /// Cancels the observation task.
  func cancel() {
    task.cancel()
  }

  private static func _run(
    backgroundStream: AsyncStream<Void>,
    foregroundStream: AsyncStream<Void>,
    client: Realtime?
  ) async {
    // Merge both event types into a single ordered stream using a shared channel.
    // We use a simple approach: run two child tasks, one for each stream, that feed
    // a common continuation.
    enum Event {
      case background
      case foreground
    }

    let (eventStream, eventCont) = AsyncStream<Event>.makeStream()

    let bgTask = Task {
      for await _ in backgroundStream {
        eventCont.yield(.background)
      }
    }
    let fgTask = Task {
      for await _ in foregroundStream {
        eventCont.yield(.foreground)
      }
    }
    defer {
      bgTask.cancel()
      fgTask.cancel()
      eventCont.finish()
    }

    var didBackgroundWhileDropped = false

    for await event in eventStream {
      if Task.isCancelled { break }
      guard let client else { break }
      switch event {
      case .background:
        // Record that we entered the background. We don't know yet if the socket
        // will survive — we check on foreground.
        didBackgroundWhileDropped = true
      case .foreground:
        guard didBackgroundWhileDropped else { continue }
        didBackgroundWhileDropped = false
        // Delegate the reconnect decision to the actor (it checks intentionalDisconnect
        // and current connection state).
        await client.handleAppForeground()
      }
    }
  }
}
