import ConcurrencyExtras
import Foundation

protocol HeartbeatTimerProtocol: Sendable {
  func start(_ handler: @escaping @Sendable () -> Void)
  func stop()
}

final class HeartbeatTimer: HeartbeatTimerProtocol, @unchecked Sendable {
  let timeInterval: TimeInterval
  let leeway: TimeInterval

  private let timer = LockIsolated(Timer?.none)

  init(timeInterval: TimeInterval, leeway: TimeInterval) {
    self.timeInterval = timeInterval
    self.leeway = leeway
  }

  func start(_ handler: @escaping () -> Void) {
    timer.withValue {
      $0?.invalidate()
      $0 = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
        handler()
      }
      $0?.tolerance = leeway
    }
  }

  func stop() {
    timer.withValue {
      $0?.invalidate()
      $0 = nil
    }
  }
}
