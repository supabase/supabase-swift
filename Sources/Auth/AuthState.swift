//
//  AuthState.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

/// Whether a user is signed in, as the client knows it in memory.
///
/// Read it with ``AuthClient/status``, or observe every change with ``AuthClient/events()``.
public enum AuthStatus: Hashable, Sendable {
  /// Storage was not read yet, or it could not be read, for example because the device is locked
  /// before the first unlock. The client reads it again later.
  case loading
  /// No user is signed in. The reason is `nil` when the client cannot tell why.
  case signedOut(SignOutReason?)
  /// A user is signed in. The session may be expired; check ``Session/isExpired``.
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
public struct SignOutReason: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
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

extension SignOutReason {
  /// The reason for an error whose ``AuthError/invalidatesSession`` is `true`.
  init(invalidatedBy error: AuthError) {
    switch error.errorCode {
    case .refreshTokenAlreadyUsed, .sessionNotFound, .userBanned:
      self = .sessionRevoked
    default:
      // refresh_token_not_found, session_expired, and an OAuth invalid_grant on refresh.
      self = .sessionExpired
    }
  }
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

  /// Why the user was signed out. Set only when ``event`` is ``AuthEvent/signedOut``.
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
