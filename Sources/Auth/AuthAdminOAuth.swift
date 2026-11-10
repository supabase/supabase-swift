//
//  AuthAdminOAuth.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

public import Foundation

/// Admin operations for managing OAuth 2.1 clients registered in Supabase Auth.
///
/// Only relevant when the OAuth 2.1 server feature is enabled in Supabase Auth.
/// Access this namespace via ``AuthAdminClient/oauth``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app — call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Managing clients
/// - ``listClients()``
/// - ``createClient(_:)``
/// - ``client(id:)``
/// - ``updateClient(id:_:)``
/// - ``deleteClient(id:)``
/// - ``regenerateClientSecret(id:)``
public struct AuthAdminOAuth: Sendable {
  let admin: AuthAdminClient

  var api: APIClient { admin.api }
  var authAPI: AuthAPI { admin.authAPI }

  /// Lists every OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// The server returns every client in one response, newest first. It does not page this list.
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func listClients() async throws -> [OAuthClient] {
    try await api.execute(authAPI.adminListOAuthClients())
  }

  /// Creates a new OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  public func createClient(_ client: CreateOAuthClient) async throws -> OAuthClient {
    try await api.execute(authAPI.adminCreateOAuthClient(client))
  }

  /// Gets details of a specific OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func client(id: UUID) async throws -> OAuthClient {
    try await api.execute(authAPI.adminOAuthClient(id: id))
  }

  /// Updates an existing OAuth client registration. Only the provided fields will be updated.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Parameter changes: The fields to update.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func updateClient(
    id: UUID,
    _ changes: UpdateOAuthClient
  ) async throws -> OAuthClient {
    try await api.execute(authAPI.adminUpdateOAuthClient(id: id, changes))
  }

  /// Deletes an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client to delete.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func deleteClient(id: UUID) async throws {
    try await api.execute(authAPI.adminDeleteOAuthClient(id: id))
  }

  /// Regenerates the secret for an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  public func regenerateClientSecret(id: UUID) async throws -> OAuthClient {
    try await api.execute(authAPI.adminRegenerateOAuthClientSecret(id: id))
  }
}
