import ConcurrencyExtras
import Foundation

protocol HeartbeatTimerProtocol: Sendable {
  func start(_ handler: @escaping @Sendable () -> Void) async
  func stop() async
}

actor HeartbeatTimer: HeartbeatTimerProtocol, @unchecked Sendable {
  let timeInterval: TimeInterval

  init(timeInterval: TimeInterval) {
    self.timeInterval = timeInterval
  }

  private var task: Task<Void, Never>?

  func start(_ handler: @escaping @Sendable () -> Void) {
    task?.cancel()
    task = Task {
      while !Task.isCancelled {
        let seconds = UInt64(timeInterval)
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * seconds)
        handler()
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}
