import Foundation
import Helpers
import Logging

enum Refresher {
  static let refreshLeadTime: Duration = .seconds(90)
  static let backoffBase: Duration = .seconds(2)
  static let backoffCap: Duration = .seconds(60)

  struct Driver: Sendable {
    var clock: any Clock<Duration>
    var logger: Logging.Logger
    var request: @Sendable (_ refreshToken: String) async throws -> Session
  }

  static func run(
    for session: Session,
    driver: Driver,
    now: @Sendable () -> Date,
    afterFailure failure: (any Error)? = nil,
    refresh: () async throws -> Void
  ) async {
    if session.hasClockSkew {
      driver.logger.warning(
        "The device clock and the server's disagree; refreshing on the local receipt time.")
    }

    var attempt = failure == nil ? 0 : 1
    var delay =
      failure.map { delayBeforeRetry(attempt: 1, after: $0, for: session, now: now()) }
      ?? delayBeforeRefresh(of: session, now: now())
    while true {
      do {
        if delay > .zero {
          try await driver.clock.sleep(for: delay)
        } else {
          try Task.checkCancellation()
        }
        try await refresh()
        return
      } catch is CancellationError where Task.isCancelled {
        return
      } catch {
        attempt += 1
        delay = delayBeforeRetry(attempt: attempt, after: error, for: session, now: now())
        driver.logger.debug("auto refresh failed, retrying in \(delay): \(error)")
      }
    }
  }

  static func delayBeforeRefresh(of session: Session, now: Date) -> Duration {
    max(.zero, session.remainingLifetime(at: now) - refreshLeadTime)
  }

  static func delayBeforeRetry(
    attempt: Int,
    after error: any Error,
    for session: Session,
    now: Date
  ) -> Duration {
    let backoff = min(backoffCap, backoffBase * (1 << min(max(attempt - 1, 0), 30)))
    let jittered = backoff / 2 + .seconds(Double.random(in: 0...(backoff / 2).timeInterval))

    let timeUntilExpiry = session.remainingLifetime(at: now)
    guard timeUntilExpiry > .zero else { return jittered }
    let retryingIsPointlessUntilExpiry = (error as? AuthError)?.invalidatesSession == true
    if retryingIsPointlessUntilExpiry {
      return max(jittered, timeUntilExpiry)
    }
    return min(jittered, timeUntilExpiry)
  }
}
