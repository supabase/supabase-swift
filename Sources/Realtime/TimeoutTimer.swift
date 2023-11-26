// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// Creates a timer that can perform calculated reties by setting
/// `timerCalculation` , such as exponential backoff.
///
/// ### Example
///
///     let reconnectTimer = TimeoutTimer()
///
///     // Receive a callbcak when the timer is fired
///     reconnectTimer.callback.delegate(to: self) { (_) in
///         print("timer was fired")
///     }
///
///     // Provide timer interval calculation
///     reconnectTimer.timerCalculation.delegate(to: self) { (_, tries) -> TimeInterval in
///         return tries > 2 ? 1000 : [1000, 5000, 10000][tries - 1]
///     }
///
///     reconnectTimer.scheduleTimeout() // fires after 1000ms
///     reconnectTimer.scheduleTimeout() // fires after 5000ms
///     reconnectTimer.reset()
///     reconnectTimer.scheduleTimeout() // fires after 1000ms

import Foundation

protocol TimeoutTimerProtocol: Sendable {
  func setHandler(_ handler: @Sendable @escaping () async -> Void) async
  func setTimerCalculation(
    _ timerCalculation: @Sendable @escaping (Int) async
      -> TimeInterval
  ) async

  func reset() async
  func scheduleTimeout() async
}

actor TimeoutTimer: TimeoutTimerProtocol {
  /// Handler to be informed when the underlying Timer fires
  private var handler: @Sendable () async -> Void = {}

  /// Provides TimeInterval to use when scheduling the timer
  private var timerCalculation: @Sendable (Int) async -> TimeInterval = { _ in 0 }

  func setHandler(_ handler: @escaping @Sendable () async -> Void) {
    self.handler = handler
  }

  func setTimerCalculation(_ timerCalculation: @escaping @Sendable (Int) async -> TimeInterval) {
    self.timerCalculation = timerCalculation
  }

  /// The work to be done when the queue fires
  private var task: Task<Void, Never>?

  /// The number of times the underlyingTimer has been set off.
  private var tries: Int = 0

  /// Resets the Timer, clearing the number of tries and stops
  /// any scheduled timeout.
  func reset() {
    tries = 0
    clearTimer()
  }

  /// Schedules a timeout callback to fire after a calculated timeout duration.
  func scheduleTimeout() async {
    // Clear any ongoing timer, not resetting the number of tries
    clearTimer()

    let timeInterval = await timerCalculation(tries + 1)

    task = Task {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeInterval))
      tries += 1
      await handler()
    }
  }

  /// Invalidates any ongoing Timer. Will not clear how many tries have been made
  private func clearTimer() {
    task?.cancel()
    task = nil
  }
}
