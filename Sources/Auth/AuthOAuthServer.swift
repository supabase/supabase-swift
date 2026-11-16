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
/// - ``getAuthorizationDetails(authorizationId:)``
/// - ``approveAuthorization(authorizationId:)``
/// - ``denyAuthorization(authorizationId:)``
///
/// ### Managing grants
/// - ``listGrants()``
/// - ``revokeGrant(clientId:)``
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
  /// - Important: Call this before ``approveAuthorization(authorizationId:)``
  ///   or ``denyAuthorization(authorizationId:)``. The authorization request
  ///   is created without an owning user (to support flows where the user
  ///   hasn't signed in yet), and this call is what claims it for the
  ///   current user server-side. Calling approve/deny first fails as if the
  ///   authorization didn't exist.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: Either the details to present for consent, or a redirect if already approved.
  @available(*, deprecated, message: "Use authorizationDetails(id:) instead.")
  public func getAuthorizationDetails(
    authorizationId: String
  ) async throws -> OAuthAuthorizationDetailsResponse {
    try await authorizationDetails(id: authorizationId)
  }

  /// Fetches the details of an authorization request, to show a consent screen.
  ///
  /// Call this before ``approveAuthorization(id:)`` or ``denyAuthorization(id:)``. It claims the
  /// request for the signed-in user.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: The details to show, or a redirect when the user already gave consent.
  public func authorizationDetails(
    id authorizationId: String
  ) async throws -> OAuthAuthorizationDetailsResult {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("oauth/authorizations")
          .appendingPathComponent(authorizationId),
        method: .get
      )
    )
    .decoded(decoder: decoder)
  }

  /// Approves a pending OAuth authorization request.
  ///
  /// - Important: ``getAuthorizationDetails(authorizationId:)`` must be
  ///   called for this `authorizationId` first — it claims the request for
  ///   the current user, without which this fails as if the authorization
  ///   didn't exist.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, completing the third-party app's OAuth flow.
  @available(*, deprecated, message: "Use approveAuthorization(id:) instead.")
  public func approveAuthorization(authorizationId: String) async throws -> OAuthRedirect {
    try await approveAuthorization(id: authorizationId)
  }

  /// Approves an authorization request for the signed-in user.
  ///
  /// Call ``authorizationDetails(id:)`` for this request first.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: The URL to send the user to.
  public func approveAuthorization(id authorizationId: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: authorizationId, action: "approve")
  }

  /// Denies a pending OAuth authorization request.
  ///
  /// This does not throw on a normal denial: the server returns a redirect
  /// URL whose query string carries an `error=access_denied` parameter
  /// (RFC 6749), which the caller should navigate the user to so the
  /// third-party app receives the OAuth error.
  ///
  /// - Important: ``getAuthorizationDetails(authorizationId:)`` must be
  ///   called for this `authorizationId` first — it claims the request for
  ///   the current user, without which this fails as if the authorization
  ///   didn't exist.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, carrying the OAuth error.
  @available(*, deprecated, message: "Use denyAuthorization(id:) instead.")
  public func denyAuthorization(authorizationId: String) async throws -> OAuthRedirect {
    try await denyAuthorization(id: authorizationId)
  }

  /// Denies an authorization request for the signed-in user.
  ///
  /// Call ``authorizationDetails(id:)`` for this request first.
  ///
  /// - Parameter id: The opaque identifier of the authorization request.
  /// - Returns: The URL to send the user to.
  public func denyAuthorization(id authorizationId: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: authorizationId, action: "deny")
  }

  private func consent(authorizationId: String, action: String) async throws -> OAuthRedirect {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("oauth/authorizations")
          .appendingPathComponent(authorizationId)
          .appendingPathComponent("consent"),
        method: .post,
        body: encoder.encode(["action": action])
      )
    )
    .decoded(decoder: decoder)
  }

  /// Lists the OAuth grants the user has given to third-party client apps.
  ///
  /// - Returns: The active grants.
  public func listGrants() async throws -> [OAuthGrant] {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("user/oauth/grants"),
        method: .get
      )
    )
    .decoded(decoder: decoder)
  }

  /// Revokes a previously granted OAuth consent.
  ///
  /// This marks the consent as revoked, deletes active sessions for that
  /// OAuth client, and invalidates its associated refresh tokens.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client to revoke access for.
  @available(*, deprecated, message: "Use revokeGrant(clientID:) instead.")
  public func revokeGrant(clientId: UUID) async throws {
    try await revokeGrant(clientID: clientId)
  }

  /// Revokes the signed-in user's grant for an OAuth client.
  ///
  /// - Parameter clientID: The ID of the client to revoke.
  public func revokeGrant(clientID clientId: UUID) async throws {
    _ = try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("user/oauth/grants"),
        method: .delete,
        query: [URLQueryItem(name: "client_id", value: clientId.uuidString)]
      )
    )
  }
}
