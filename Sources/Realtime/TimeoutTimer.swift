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

import ConcurrencyExtras
import Foundation

protocol TimeoutTimerProtocol: Sendable {
  func setHandler(_ handler: @Sendable @escaping () -> Void)
  func setTimerCalculation(_ timerCalculation: @Sendable @escaping (Int) -> TimeInterval)
  func reset()
  func scheduleTimeout()
}

final class TimeoutTimer: TimeoutTimerProtocol, @unchecked Sendable {
  private let lock = NSRecursiveLock()

  private var handler: (@Sendable () -> Void)?
  private var timerCalculation: (@Sendable (Int) -> TimeInterval)?
  private var tries: Int = 0
  private var task: Task<Void, Never>?

  func setHandler(_ handler: @escaping @Sendable () -> Void) {
    lock.withLock {
      self.handler = handler
    }
  }

  func setTimerCalculation(_ timerCalculation: @escaping @Sendable (Int) -> TimeInterval) {
    lock.withLock {
      self.timerCalculation = timerCalculation
    }
  }

  func reset() {
    lock.withLock {
      tries = 0
      task?.cancel()
      task = nil
    }
  }

  func scheduleTimeout() {
    lock.lock()
    defer { lock.unlock() }

    task?.cancel()
    task = nil

    let timeInterval = timerCalculation?(tries + 1) ?? 5.0

    task = Task {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeInterval))

      lock.withLock {
        self.tries += 1
        self.handler?()
      }
    }
  }
}
