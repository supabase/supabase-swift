import Foundation
import Helpers

/// A session together with the local time the client received it.
///
/// The refresh deadline is `receivedAt + expiresIn` on the local clock, so a device clock that
/// disagrees with the server's cannot move it. `Session.expiresAt` stays the server's value.
struct ReceivedSession: Hashable, Sendable {
  static let clockSkewTolerance: Duration = .seconds(60)

  var session: Session
  var receivedAt: Date

  /// For a session that did not record its receipt, such as one stored by v2: the server's issue
  /// time, `expiresAt - expiresIn`.
  init(session: Session) {
    self.init(
      session: session,
      receivedAt: Date(timeIntervalSince1970: session.expiresAt - session.expiresIn)
    )
  }

  init(session: Session, receivedAt: Date) {
    self.session = session
    self.receivedAt = receivedAt
  }

  /// When the access token expires, on the local clock.
  ///
  /// The server's `expiresAt` moves it earlier only within ``clockSkewTolerance``, which covers
  /// network latency and an implicit-flow URL opened a little late.
  var expiryDate: Date {
    let local = localExpiryDate
    let server = serverExpiryDate
    // Beyond the tolerance the server value is on another clock. Bounding by it would make a
    // device clock that runs ahead see every new token as expired and refresh in a loop.
    if server < local, local.timeIntervalSince(server) <= Self.clockSkewTolerance.timeInterval {
      return server
    }
    return local
  }

  var hasClockSkew: Bool {
    abs(localExpiryDate.timeIntervalSince(serverExpiryDate))
      > Self.clockSkewTolerance.timeInterval
  }

  func expiresIn(at date: Date) -> Duration {
    .seconds(expiryDate.timeIntervalSince(date))
  }

  func isExpired(at date: Date, leeway: Duration) -> Bool {
    expiresIn(at: date) < leeway
  }

  private var localExpiryDate: Date {
    receivedAt.addingTimeInterval(session.expiresIn)
  }

  private var serverExpiryDate: Date {
    Date(timeIntervalSince1970: session.expiresAt)
  }
}
