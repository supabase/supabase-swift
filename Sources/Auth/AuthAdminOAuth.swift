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
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }

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
        url: configuration.url.appendingPathComponent("admin/oauth/clients"),
        query: [
          URLQueryItem(name: "page", value: params?.page?.description ?? ""),
          URLQueryItem(name: "per_page", value: params?.perPage?.description ?? ""),
        ]
      )
    )

    let response = try data.decoded(
      as: Response.self, decoder: configuration.resolvedDecoder)

    var pagination = ListOAuthClientsPaginatedResponse(
      clients: response.clients,
      audience: response.aud,
      lastPage: 0,
      total: httpResponse.headerFields[.xTotalCount].flatMap(Int.init) ?? 0
    )

    let links = httpResponse.headerFields[.link]?.components(separatedBy: ",") ?? []
    if !links.isEmpty {
      for link in links {
        let page = link.components(separatedBy: ";")[0].components(separatedBy: "=")[1].prefix(
          while: \.isNumber
        )
        let rel = link.components(separatedBy: ";")[1].components(separatedBy: "=")[1]

        if rel == "\"last\"", let lastPage = Int(page) {
          pagination.lastPage = lastPage
        } else if rel == "\"next\"", let nextPage = Int(page) {
          pagination.nextPage = nextPage
        }
      }
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
        url: configuration.url.appendingPathComponent("admin/oauth/clients")
      ), body: encoder.encode(params)
    )
    .decoded(decoder: configuration.resolvedDecoder)
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
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(id)")
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
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
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(id)")
      ), body: configuration.resolvedEncoder.encode(params)
    )
    .decoded(decoder: configuration.resolvedDecoder)
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
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(id)")
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
        url: configuration.url
          .appendingPathComponent("admin/oauth/clients/\(id)/regenerate_secret")
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }
}
