//
//  AuthOAuthServer.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

public import Foundation
import HTTPTypes

/// The OAuth 2.1 authorization-server consent and grant-management API.
///
/// Lets the signed-in user approve or deny a pending OAuth authorization
/// request from a third-party app registered against this project, and view
/// or revoke grants they've already given.
///
/// Access this namespace via ``AuthClient/oauthServer``.
///
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth. Not
/// to be confused with ``AuthAdmin/oauth``, which manages OAuth *client*
/// registrations (an admin-only, secret-key operation).
///
/// ## Topics
///
/// ### Handling a pending authorization
/// - ``authorizationDetails(id:)``
/// - ``approveAuthorization(id:)``
/// - ``denyAuthorization(id:)``
///
/// ### Managing grants
/// - ``listGrants()``
/// - ``revokeGrant(id:)``
public struct AuthOAuthServer: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }
  var decoder: JSONDecoder { Dependencies[clientID].resolvedDecoder }

  /// Fetches details about a pending OAuth authorization request, to present
  /// a consent screen to the user.
  ///
  /// If the user already has an active consent covering the requested
  /// scopes for this client, the server auto-approves the request and this
  /// returns ``OAuthAuthorizationDetailsResponse/redirect(_:)`` instead of
  /// ``OAuthAuthorizationDetailsResponse/details(_:)`` — callers must handle
  /// both cases.
  ///
  /// - Important: Call this before ``approveAuthorization(id:)``
  ///   or ``denyAuthorization(id:)``. The authorization request
  ///   is created without an owning user (to support flows where the user
  ///   hasn't signed in yet), and this call is what claims it for the
  ///   current user server-side. Calling approve/deny first fails as if the
  ///   authorization didn't exist.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: Either the details to present for consent, or a redirect if already approved.
  public func authorizationDetails(
    id: String
  ) async throws -> OAuthAuthorizationDetailsResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        method: .get,
        url: configuration.url
          .appendingPathComponent("oauth/authorizations")
          .appendingPathComponent(id)
      )
    )
    .decoded(decoder: decoder)
  }

  /// Approves a pending OAuth authorization request.
  ///
  /// - Important: ``authorizationDetails(id:)`` must be
  ///   called for this `id` first — it claims the request for
  ///   the current user, without which this fails as if the authorization
  ///   didn't exist.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, completing the third-party app's OAuth flow.
  public func approveAuthorization(id: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: id, action: "approve")
  }

  /// Denies a pending OAuth authorization request.
  ///
  /// This does not throw on a normal denial: the server returns a redirect
  /// URL whose query string carries an `error=access_denied` parameter
  /// (RFC 6749), which the caller should navigate the user to so the
  /// third-party app receives the OAuth error.
  ///
  /// - Important: ``authorizationDetails(id:)`` must be
  ///   called for this `id` first — it claims the request for
  ///   the current user, without which this fails as if the authorization
  ///   didn't exist.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, carrying the OAuth error.
  public func denyAuthorization(id: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: id, action: "deny")
  }

  private func consent(authorizationId: String, action: String) async throws -> OAuthRedirect {
    try await api.authorizedExecute(
      HTTPRequest(
        method: .post,
        url: configuration.url
          .appendingPathComponent("oauth/authorizations")
          .appendingPathComponent(authorizationId)
          .appendingPathComponent("consent")
      ), body: encoder.encode(["action": action])
    )
    .decoded(decoder: decoder)
  }

  /// Lists the OAuth grants the user has given to third-party client apps.
  ///
  /// - Returns: The active grants.
  public func listGrants() async throws -> [OAuthGrant] {
    try await api.authorizedExecute(
      HTTPRequest(
        method: .get,
        url: configuration.url.appendingPathComponent("user/oauth/grants")
      )
    )
    .decoded(decoder: decoder)
  }

  /// Revokes a previously granted OAuth consent.
  ///
  /// This marks the consent as revoked, deletes active sessions for that
  /// OAuth client, and invalidates its associated refresh tokens.
  ///
  /// - Parameter id: The unique identifier of the OAuth client to revoke access for.
  public func revokeGrant(id: UUID) async throws {
    _ = try await api.authorizedExecute(
      HTTPRequest(
        method: .delete,
        url: configuration.url.appendingPathComponent("user/oauth/grants"),
        query: [URLQueryItem(name: "client_id", value: id.uuidString)]
      )
    )
  }
}
