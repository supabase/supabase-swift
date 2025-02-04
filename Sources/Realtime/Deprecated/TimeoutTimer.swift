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

// sourcery: AutoMockable
class TimeoutTimer {
  /// Callback to be informed when the underlying Timer fires
  var callback = Delegated<Void, Void>()

  /// Provides TimeInterval to use when scheduling the timer
  var timerCalculation = Delegated<Int, TimeInterval>()

  /// The work to be done when the queue fires
  var workItem: DispatchWorkItem?

  /// The number of times the underlyingTimer hass been set off.
  var tries: Int = 0

  /// The Queue to execute on. In testing, this is overridden
  var queue: TimerQueue = .main

  /// Resets the Timer, clearing the number of tries and stops
  /// any scheduled timeout.
  func reset() {
    tries = 0
    clearTimer()
  }

  /// Schedules a timeout callback to fire after a calculated timeout duration.
  func scheduleTimeout() {
    // Clear any ongoing timer, not resetting the number of tries
    clearTimer()

    // Get the next calculated interval, in milliseconds. Do not
    // start the timer if the interval is returned as nil.
    guard let timeInterval = timerCalculation.call(tries + 1) else { return }

    let workItem = DispatchWorkItem {
      self.tries += 1
      self.callback.call()
    }

    self.workItem = workItem
    queue.queue(timeInterval: timeInterval, execute: workItem)
  }

  /// Invalidates any ongoing Timer. Will not clear how many tries have been made
  private func clearTimer() {
    workItem?.cancel()
    workItem = nil
  }
}

/// Wrapper class around a DispatchQueue. Allows for providing a fake clock
/// during tests.
class TimerQueue {
  // Can be overriden in tests
  static var main = TimerQueue()

  func queue(timeInterval: TimeInterval, execute: DispatchWorkItem) {
    // TimeInterval is always in seconds. Multiply it by 1000 to convert
    // to milliseconds and round to the nearest millisecond.
    let dispatchInterval = Int(round(timeInterval * 1000))

    let dispatchTime = DispatchTime.now() + .milliseconds(dispatchInterval)
    DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: execute)
  }
}
