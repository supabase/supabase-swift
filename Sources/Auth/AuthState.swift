/// Whether a user is signed in, as the client knows it.
///
/// Read it with ``AuthClient/status``, or observe every change with ``AuthClient/events()``.
public enum AuthStatus: Hashable, Sendable {
  /// Storage was not read yet. This version of the client reads storage on demand, so it never
  /// reports this status.
  case loading

  /// No user is signed in. The reason is `nil` when the client cannot tell why.
  case signedOut(SignOutReason?)

  /// A user is signed in. The session may be expired; check ``Session/isExpired(at:leeway:)``.
  case signedIn(Session)

  var session: Session? {
    guard case .signedIn(let session) = self else { return nil }
    return session
  }
}

/// Why no user is signed in.
///
/// New reasons can be added in a minor release, so a `switch` over this value needs a `default:`
/// case.
///
/// This version of the client does not record why a session ended, so the changes that
/// ``AuthClient/events()`` delivers carry no reason.
public struct SignOutReason: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The name of the reason, such as `"userInitiated"`.
  public let rawValue: String

  /// Creates a ``SignOutReason`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``SignOutReason`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The app called ``AuthClient/signOut(scope:)``.
  public static let userInitiated: SignOutReason = "userInitiated"

  /// The server reported that the session expired or that it no longer knows the refresh token.
  public static let sessionExpired: SignOutReason = "sessionExpired"

  /// The server revoked the session: its refresh token was already used, the session is gone,
  /// or the user is banned.
  public static let sessionRevoked: SignOutReason = "sessionRevoked"

  /// Storage held no usable session.
  public static let sessionMissing: SignOutReason = "sessionMissing"
}

/// One change of the auth status, as delivered by ``AuthClient/events()``.
public struct AuthChange: Hashable, Sendable {
  /// What caused the change.
  public let event: AuthEvent

  /// The status after the change.
  public let status: AuthStatus

  /// The session after the change, or `nil` when no user is signed in.
  public var session: Session? {
    status.session
  }

  /// Why the user was signed out. Set only when ``event`` is ``AuthChangeEvent/signedOut``.
  public var signOutReason: SignOutReason? {
    guard event == .signedOut, case .signedOut(let reason) = status else { return nil }
    return reason
  }

  /// Creates a change, for example to feed a fake stream in your app's tests.
  public init(event: AuthEvent, status: AuthStatus) {
    self.event = event
    self.status = status
  }
}

extension AuthChange: CustomStringConvertible {
  /// The event and the status. A session in the status prints as its user ID, with no token.
  public var description: String {
    let status =
      switch status {
      case .loading: "loading"
      case .signedOut(let reason): "signedOut(\(reason?.rawValue ?? "nil"))"
      case .signedIn(let session): "signedIn(user: \(session.user.id))"
      }
    return "AuthChange(event: \(event.rawValue), status: \(status))"
  }
}
