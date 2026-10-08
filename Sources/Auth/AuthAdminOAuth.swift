//
//  AuthAdminOAuth.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

public import Foundation
import HTTPTypes

/// Admin operations for managing OAuth 2.1 clients registered in Supabase Auth.
///
/// Only relevant when the OAuth 2.1 server feature is enabled in Supabase Auth.
/// Access this namespace via ``AuthAdmin/oauth``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app — call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Managing clients
/// - ``listClients(params:)``
/// - ``createClient(params:)``
/// - ``client(id:)``
/// - ``updateClient(id:params:)``
/// - ``deleteClient(id:)``
/// - ``regenerateClientSecret(id:)``
public struct AuthAdminOAuth: Sendable {
  let admin: AuthAdmin

  var url: URL { admin.url }
  var api: APIClient { admin.api }
  var encoder: JSONEncoder { admin.encoder }
  var decoder: JSONDecoder { admin.decoder }

  /// Lists all OAuth clients with optional pagination.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func listClients(
    params: PageParams? = nil
  ) async throws -> ListOAuthClientsPaginatedResponse {
    struct Response: Decodable {
      let clients: [OAuthClient]
      let aud: String
    }

    let (httpResponse, data) = try await api.send(
      HTTPRequest(
        method: .get,
        url: url.appendingPathComponent("admin/oauth/clients"),
        query: [
          params?.page.map { URLQueryItem(name: "page", value: $0.description) },
          params?.perPage.map { URLQueryItem(name: "per_page", value: $0.description) },
        ].compactMap { $0 }
      )
    )

    let response = try data.decoded(
      as: Response.self, decoder: decoder)

    var pagination = ListOAuthClientsPaginatedResponse(
      clients: response.clients,
      audience: response.aud,
      lastPage: 0,
      total: httpResponse.headerFields[.xTotalCount].flatMap(Int.init) ?? 0
    )

    let pages = parsePaginationLinks(httpResponse.headerFields[.link])
    if let lastPage = pages["last"] {
      pagination.lastPage = lastPage
    }
    if let nextPage = pages["next"] {
      pagination.nextPage = nextPage
    }

    return pagination
  }

  /// Creates a new OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  public func createClient(params: CreateOAuthClientParams) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: url.appendingPathComponent("admin/oauth/clients")
      ), body: encoder.encode(params)
    )
    .decoded(decoder: decoder)
  }

  /// Gets details of a specific OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func client(id: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: url.appendingPathComponent("admin/oauth/clients/\(id)")
      )
    )
    .decoded(decoder: decoder)
  }

  /// Updates an existing OAuth client registration. Only the provided fields will be updated.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Parameter params: The fields to update.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func updateClient(
    id: UUID,
    params: UpdateOAuthClientParams
  ) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        method: .put,
        url: url.appendingPathComponent("admin/oauth/clients/\(id)")
      ), body: encoder.encode(params)
    )
    .decoded(decoder: decoder)
  }

  /// Deletes an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client to delete.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func deleteClient(id: UUID) async throws {
    _ = try await api.execute(
      HTTPRequest(
        method: .delete,
        url: url.appendingPathComponent("admin/oauth/clients/\(id)")
      )
    )
  }

  /// Regenerates the secret for an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter id: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  public func regenerateClientSecret(id: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url:
          url
          .appendingPathComponent("admin/oauth/clients/\(id)/regenerate_secret")
      )
    )
    .decoded(decoder: decoder)
  }
}
