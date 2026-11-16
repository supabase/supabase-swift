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
/// - ``getClient(clientId:)``
/// - ``updateClient(clientId:params:)``
/// - ``deleteClient(clientId:)``
/// - ``regenerateClientSecret(clientId:)``
public struct AuthAdminOAuth: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }

  /// Lists all OAuth clients with optional pagination.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @available(
    *, deprecated,
    message: "Use listClients() instead. Annotate the result as [OAuthClient] to select it."
  )
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

    let response = try httpResponse.decoded(
      as: Response.self, decoder: configuration.resolvedDecoder)

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
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  @available(*, deprecated, message: "Use createClient(_:) instead.")
  public func createClient(params: CreateOAuthClientParams) async throws -> OAuthClient {
    try await _createClient(body: params)
  }

  /// Creates a new OAuth client.
  ///
  /// - Parameter client: The client to create.
  /// - Returns: The created client, with its secret.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @discardableResult
  public func createClient(_ client: CreateOAuthClient) async throws -> OAuthClient {
    try await _createClient(body: client)
  }

  private func _createClient(body params: some Encodable) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients"),
        method: .post,
        body: encoder.encode(params)
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Gets details of a specific OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @available(*, deprecated, message: "Use client(id:) instead.")
  public func getClient(clientId: UUID) async throws -> OAuthClient {
    try await client(id: clientId)
  }

  /// Fetches an OAuth client by ID.
  ///
  /// - Parameter id: The ID of the client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  public func client(id clientId: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .get
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Updates an existing OAuth client registration. Only the provided fields will be updated.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Parameter params: The fields to update.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @available(*, deprecated, message: "Use updateClient(id:_:) instead.")
  public func updateClient(
    clientId: UUID,
    params: UpdateOAuthClientParams
  ) async throws -> OAuthClient {
    try await _updateClient(id: clientId, body: params)
  }

  /// Updates an OAuth client. The server changes only the fields you set.
  ///
  /// - Parameters:
  ///   - id: The ID of the client to update.
  ///   - changes: The changes to make.
  /// - Returns: The updated client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @discardableResult
  public func updateClient(
    id: UUID,
    _ changes: UpdateOAuthClient
  ) async throws -> OAuthClient {
    try await _updateClient(id: id, body: changes)
  }

  private func _updateClient(
    id clientId: UUID,
    body params: some Encodable
  ) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .put,
        body: configuration.resolvedEncoder.encode(params)
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Deletes an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client to delete.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @available(*, deprecated, message: "Use deleteClient(id:) instead.")
  public func deleteClient(clientId: UUID) async throws {
    try await deleteClient(id: clientId)
  }

  /// Deletes an OAuth client.
  ///
  /// - Parameter id: The ID of the client to delete.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  public func deleteClient(id clientId: UUID) async throws {
    _ = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients/\(clientId)"),
        method: .delete
      )
    )
  }

  /// Regenerates the secret for an OAuth client.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  @available(*, deprecated, message: "Use regenerateClientSecret(id:) instead.")
  public func regenerateClientSecret(clientId: UUID) async throws -> OAuthClient {
    try await regenerateClientSecret(id: clientId)
  }

  /// Creates a new secret for an OAuth client. The old secret stops working.
  ///
  /// - Parameter id: The ID of the client.
  /// - Returns: The client, with its new secret.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @discardableResult
  public func regenerateClientSecret(id clientId: UUID) async throws -> OAuthClient {
    try await api.execute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("admin/oauth/clients/\(clientId)/regenerate_secret"),
        method: .post
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Lists the OAuth clients of the project.
  ///
  /// The call needs a result type of `[OAuthClient]` to select this overload:
  ///
  /// ```swift
  /// let clients: [OAuthClient] = try await supabase.auth.admin.oauth.listClients()
  /// ```
  ///
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  @_disfavoredOverload
  public func listClients() async throws -> [OAuthClient] {
    struct Response: Decodable {
      let clients: [OAuthClient]?
    }

    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/oauth/clients"),
        method: .get
      )
    )
    .decoded(as: Response.self, decoder: configuration.resolvedDecoder)
    .clients ?? []
  }
}
