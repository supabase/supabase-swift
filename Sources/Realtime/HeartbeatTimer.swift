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

import Foundation

/// Heartbeat Timer class which manages the lifecycle of the underlying
/// timer which triggers when a heartbeat should be fired. This heartbeat
/// runs on it's own Queue so that it does not interfere with the main
/// queue but guarantees thread safety.
class HeartbeatTimer {
  // ----------------------------------------------------------------------

  // MARK: - Dependencies

  // ----------------------------------------------------------------------
  // The interval to wait before firing the Timer
  let timeInterval: TimeInterval

  /// The maximum amount of time which the system may delay the delivery of the timer events
  let leeway: DispatchTimeInterval

  // The DispatchQueue to schedule the timers on
  let queue: DispatchQueue

  // UUID which specifies the Timer instance. Verifies that timers are different
  let uuid: String = UUID().uuidString

  // ----------------------------------------------------------------------

  // MARK: - Properties

  // ----------------------------------------------------------------------
  // The underlying, cancelable, resettable, timer.
  private var temporaryTimer: DispatchSourceTimer?
  // The event handler that is called by the timer when it fires.
  private var temporaryEventHandler: (() -> Void)?

  /**
     Create a new HeartbeatTimer

     - Parameters:
       - timeInterval: Interval to fire the timer. Repeats
       - queue: Queue to schedule the timer on
       - leeway: The maximum amount of time which the system may delay the delivery of the timer events
     */
  init(
    timeInterval: TimeInterval, queue: DispatchQueue = Defaults.heartbeatQueue,
    leeway: DispatchTimeInterval = Defaults.heartbeatLeeway
  ) {
    self.timeInterval = timeInterval
    self.queue = queue
    self.leeway = leeway
  }

  /**
     Create a new HeartbeatTimer

     - Parameter timeInterval: Interval to fire the timer. Repeats
     */
  convenience init(timeInterval: TimeInterval) {
    self.init(timeInterval: timeInterval, queue: Defaults.heartbeatQueue)
  }

  func start(eventHandler: @escaping () -> Void) {
    queue.sync {
      // Create a new DispatchSourceTimer, passing the event handler
      let timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
      timer.setEventHandler(handler: eventHandler)

      // Schedule the timer to first fire in `timeInterval` and then
      // repeat every `timeInterval`
      timer.schedule(
        deadline: DispatchTime.now() + self.timeInterval,
        repeating: self.timeInterval,
        leeway: self.leeway
      )

      // Start the timer
      timer.resume()
      self.temporaryEventHandler = eventHandler
      self.temporaryTimer = timer
    }
  }

  func stop() {
    // Must be queued synchronously to prevent threading issues.
    queue.sync {
      // DispatchSourceTimer will automatically cancel when released
      temporaryTimer = nil
      temporaryEventHandler = nil
    }
  }

  /**
     True if the Timer exists and has not been cancelled. False otherwise
     */
  var isValid: Bool {
    guard let timer = temporaryTimer else { return false }
    return !timer.isCancelled
  }

  /**
     Calls the Timer's event handler immediately. This method
     is primarily used in tests (not ideal)
     */
  func fire() {
    guard isValid else { return }
    temporaryEventHandler?()
  }
}

extension HeartbeatTimer: Equatable {
  static func == (lhs: HeartbeatTimer, rhs: HeartbeatTimer) -> Bool {
    return lhs.uuid == rhs.uuid
  }
}
