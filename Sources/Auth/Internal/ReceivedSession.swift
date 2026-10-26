import Foundation

/// A session together with the local time the client received it.
///
/// The refresh deadline is `receivedAt + expiresIn` on the local clock, so a device clock that
/// disagrees with the server's cannot move it. `Session.expiresAt` stays the server's value.
struct ReceivedSession: Hashable, Sendable {
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
}
