import ConcurrencyExtras
import Foundation

struct HeartbeatTimer: Sendable {
  var start: @Sendable (_ handler: @escaping @Sendable () -> Void) -> Void
  var stop: @Sendable () -> Void
}

extension HeartbeatTimer {
  static func `default`(timeInterval: TimeInterval) -> Self {
    let task = LockIsolated(Task<Void, Never>?.none)

    return Self(
      start: { handler in
        task.withValue {
          $0?.cancel()
          $0 = Task {
            while !Task.isCancelled {
              let seconds = UInt64(timeInterval)
              try? await Task.sleep(nanoseconds: NSEC_PER_SEC * seconds)
              handler()
            }
          }
        }
      },
      stop: {
        task.withValue {
          $0?.cancel()
          $0 = nil
        }
      }
    )
  }
}
