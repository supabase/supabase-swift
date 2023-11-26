import ConcurrencyExtras
import Foundation

protocol HeartbeatTimerProtocol: Sendable {
  func start(_ handler: @escaping @Sendable () async -> Void)
  func stop()
}

final class HeartbeatTimer: HeartbeatTimerProtocol, @unchecked Sendable {
  let timeInterval: TimeInterval

  init(timeInterval: TimeInterval) {
    self.timeInterval = timeInterval
  }

  private let task = LockIsolated(Task<Void, Never>?.none)

  func start(_ handler: @escaping @Sendable () async -> Void) {
    task.withValue {
      $0?.cancel()
      $0 = Task {
        while !Task.isCancelled {
          let seconds = UInt64(timeInterval)
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * seconds)
          await handler()
        }
      }
    }
  }

  func stop() {
    task.withValue {
      $0?.cancel()
      $0 = nil
    }
  }
}
