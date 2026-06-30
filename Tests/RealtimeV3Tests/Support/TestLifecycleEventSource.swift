//
//  TestLifecycleEventSource.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

@testable import RealtimeV3

/// A test double for `LifecycleEventSource` that allows tests to programmatically
/// emit background and foreground events.
final class TestLifecycleEventSource: LifecycleEventSource, @unchecked Sendable {
  let didEnterBackground: AsyncStream<Void>
  let willEnterForeground: AsyncStream<Void>

  private let backgroundContinuation: AsyncStream<Void>.Continuation
  private let foregroundContinuation: AsyncStream<Void>.Continuation

  init() {
    let (bgStream, bgCont) = AsyncStream<Void>.makeStream()
    let (fgStream, fgCont) = AsyncStream<Void>.makeStream()
    self.didEnterBackground = bgStream
    self.willEnterForeground = fgStream
    self.backgroundContinuation = bgCont
    self.foregroundContinuation = fgCont
  }

  deinit {
    backgroundContinuation.finish()
    foregroundContinuation.finish()
  }

  /// Emit a background event (simulating the app entering the background).
  func sendBackground() {
    backgroundContinuation.yield(())
  }

  /// Emit a foreground event (simulating the app returning to the foreground).
  func sendForeground() {
    foregroundContinuation.yield(())
  }
}
