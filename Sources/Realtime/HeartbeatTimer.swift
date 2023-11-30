import ConcurrencyExtras
import Foundation

struct HeartbeatTimer: Sendable {
  var start: @Sendable (_ handler: @escaping @Sendable () -> Void) -> Void
  var stop: @Sendable () -> Void
}

extension HeartbeatTimer {
  static func timer(timeInterval: TimeInterval, leeway: TimeInterval) -> Self {
    let timer = LockIsolated(Timer?.none)

    return Self(
      start: { handler in
        timer.withValue {
          $0?.invalidate()
          $0 = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
            handler()
          }
          $0?.tolerance = leeway
        }
      },
      stop: {
        timer.withValue {
          $0?.invalidate()
          $0 = nil
        }
      }
    )
  }
}
