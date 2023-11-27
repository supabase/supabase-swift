import ConcurrencyExtras
import Foundation

protocol HeartbeatTimerProtocol: Sendable {
  func start(_ handler: @escaping @Sendable () async -> Void) async
  func stop() async
}

actor HeartbeatTimer: HeartbeatTimerProtocol, @unchecked Sendable {
  let timeInterval: TimeInterval

  init(timeInterval: TimeInterval) {
    self.timeInterval = timeInterval
  }

  private var task: Task<Void, Never>?

  func start(_ handler: @escaping @Sendable () async -> Void) {
    task?.cancel()
    task = Task {
      while !Task.isCancelled {
        let seconds = UInt64(timeInterval)
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * seconds)
        await handler()
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}
