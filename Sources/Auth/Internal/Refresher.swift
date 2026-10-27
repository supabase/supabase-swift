import Foundation
import Helpers
import Logging

struct Refresher {
  static let refreshLeadTime: Duration = .seconds(90)
  static let backoffBase: Duration = .seconds(2)
  static let backoffCap: Duration = .seconds(60)

  struct Driver: Sendable {
    var clock: any Clock<Duration>
    var logger: Logging.Logger
    var request: @Sendable (_ refreshToken: String) async throws -> Session
  }

  private struct Entry {
    var owner: UUID
    var driver: Driver
  }

  private var entries: [Entry] = []

  var task: Task<Void, Never>? {
    didSet { oldValue?.cancel() }
  }

  var activeDriver: Driver? {
    entries.last?.driver
  }

  mutating func add(_ driver: Driver, for owner: UUID) {
    remove(owner)
    entries.append(Entry(owner: owner, driver: driver))
  }

  mutating func remove(_ owner: UUID) {
    entries.removeAll { $0.owner == owner }
  }

  func isDriven(by owner: UUID) -> Bool {
    entries.contains { $0.owner == owner }
  }

  static func run(
    for received: ReceivedSession,
    driver: Driver,
    now: @Sendable () -> Date,
    refresh: () async throws -> Void
  ) async {
    if received.hasClockSkew {
      driver.logger.warning(
        "The device clock and the server's disagree; refreshing on the local receipt time.")
    }

    var delay = delayBeforeRefresh(of: received, now: now())
    var attempt = 0
    while true {
      do {
        if delay > .zero {
          try await driver.clock.sleep(for: delay)
        } else {
          try Task.checkCancellation()
        }
        try await refresh()
        return
      } catch is CancellationError {
        return
      } catch {
        attempt += 1
        delay = delayBeforeRetry(attempt: attempt, after: error, for: received, now: now())
        driver.logger.debug("auto refresh failed, retrying in \(delay): \(error)")
      }
    }
  }

  static func delayBeforeRefresh(of received: ReceivedSession, now: Date) -> Duration {
    max(.zero, received.expiresIn(at: now) - refreshLeadTime)
  }

  static func delayBeforeRetry(
    attempt: Int,
    after error: any Error,
    for received: ReceivedSession,
    now: Date
  ) -> Duration {
    let backoff = min(backoffCap, backoffBase * (1 << min(max(attempt - 1, 0), 30)))
    let jittered = backoff / 2 + .seconds(Double.random(in: 0...(backoff / 2).timeInterval))

    let timeUntilExpiry = received.expiresIn(at: now)
    guard timeUntilExpiry > .zero else { return jittered }
    let retryingIsPointlessUntilExpiry = (error as? AuthError)?.invalidatesSession == true
    if retryingIsPointlessUntilExpiry {
      return max(jittered, timeUntilExpiry)
    }
    return min(jittered, timeUntilExpiry)
  }
}
