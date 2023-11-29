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
  func setHandler(_ handler: @Sendable @escaping () async -> Void) async
  func setTimerCalculation(
    _ timerCalculation: @Sendable @escaping (Int) async
      -> TimeInterval
  ) async

  func reset() async
  func scheduleTimeout() async
}

struct TimeoutTimer: Sendable {
  var handler: @Sendable (_ handler: @Sendable @escaping () -> Void) -> Void
  var timerCalculation: @Sendable (_ timerCalculation: @Sendable @escaping (Int) -> TimeInterval)
    -> Void

  var reset: @Sendable () -> Void
  var scheduleTimeout: @Sendable () -> Void
}

extension TimeoutTimer {
  static func `default`() -> Self {
    struct State: Sendable {
      var handler: @Sendable () -> Void = {}
      var timerCalculation: @Sendable (Int) -> TimeInterval = { _ in 0.0 }
      var task: Task<Void, Never>?
      var tries: Int = 0
    }

    let state = LockIsolated(State())

    return Self(
      handler: { handler in
        state.withValue { $0.handler = handler }
      },
      timerCalculation: { timerCalculation in
        state.withValue { $0.timerCalculation = timerCalculation }
      },
      reset: {
        state.withValue {
          $0.tries = 0
          $0.task?.cancel()
          $0.task = nil
        }
      },
      scheduleTimeout: {
        let timeInterval = state.withValue {
          $0.task?.cancel()
          $0.task = nil
          return $0.timerCalculation($0.tries)
        }

        let task = Task {
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(timeInterval))
          state.withValue {
            $0.tries += 1
            $0.handler()
          }
        }

        state.withValue {
          $0.task = task
        }
      }
    )
  }
}
