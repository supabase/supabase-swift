//
//  AuthAdminOAuth.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

import Foundation
import HTTPTypes

/// Contains all OAuth client administration methods.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct AuthAdminOAuth: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].encoder }

  /// Lists all OAuth clients with optional pagination.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the client.
  public func listClients(
    params: PageParams? = nil
  ) async throws -> ListOAuthClientsPaginatedResponse {
    struct Response: Decodable {
      let clients: [OAuthClient]
      let aud: String
    }

    let httpResponse = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients"),
        method: .get,
        query: [
          URLQueryItem(name: "page", value: params?.page?.description ?? ""),
          URLQueryItem(name: "per_page", value: params?.perPage?.description ?? ""),
        ]
      )
    )

    let response = try httpResponse.decoded(as: Response.self, decoder: configuration.decoder)

    var pagination = ListOAuthClientsPaginatedResponse(
      clients: response.clients,
      aud: response.aud,
      lastPage: 0,
      total: httpResponse.headers[.xTotalCount].flatMap(Int.init) ?? 0
    )

    let links = httpResponse.headers[.link]?.components(separatedBy: ",") ?? []
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
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the client.
  @discardableResult
  public func createClient(params: CreateOAuthClientParams) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients"),
        method: .post,
        body: encoder.encode(params)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Gets details of a specific OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the client.
  public func getClient(_ clientId: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .get
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Updates as existing OAuth client registration. Only the provided fields will be updated.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Parameter params: The fields for updated.
  /// - Note: The funciton should only be called on a server. Never expose your `service_role` key in the client.
  public func updateClient(
    _ clientId: UUID,
    params: UpdateOAuthClientParams
  ) async throws -> OAuthClient {
    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .put,
        body: configuration.encoder.encode(params)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Deletes an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client to delete.
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the client.
  @discardableResult
  public func deleteClient(_ clientId: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .delete
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Regenerates the secret for an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the client.
  @discardableResult
  public func regenerateClientSecret(_ clientId: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("admin/oauth/clients/\(clientId)/regenerate_secret"),
        method: .post
      )
    )
    .decoded(decoder: configuration.decoder)
  }
}
