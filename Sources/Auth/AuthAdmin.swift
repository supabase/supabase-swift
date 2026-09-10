//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

public import Foundation
import HTTPTypes

/// Admin-only Auth operations that require the secret key.
///
/// Access this namespace via ``AuthClient/admin``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app — call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### User management
/// - ``getUserById(_:)``
/// - ``updateUserById(_:attributes:)``
/// - ``createUser(attributes:)``
/// - ``inviteUserByEmail(_:data:redirectTo:)``
/// - ``deleteUser(id:shouldSoftDelete:)``
/// - ``listUsers(params:)``
/// - ``generateLink(params:)``
/// - ``signOut(jwt:scope:)``
///
/// ### OAuth 2.1 clients
/// - ``oauth``
public struct AuthAdmin: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].resolvedEncoder }

  /// Contains all OAuth client administration methods.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Warning: This property requires `secret` key. Be careful to never expose your `secret` key in the browser.
  public var oauth: AuthAdminOAuth {
    AuthAdminOAuth(clientID: clientID)
  }

  /// Get user by id.
  /// - Parameter uid: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  public func getUserById(_ uid: UUID) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: configuration.url.appendingPathComponent("admin/users/\(uid)")
      )
    ).decoded(decoder: configuration.resolvedDecoder)
  }

  /// Updates the user data.
  /// - Parameters:
  ///   - uid: The user id you want to update.
  ///   - attributes: The data you want to update.
  @discardableResult
  public func updateUserById(_ uid: UUID, attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .put,
        url: configuration.url.appendingPathComponent("admin/users/\(uid)")
      ), body: configuration.resolvedEncoder.encode(attributes)
    ).decoded(decoder: configuration.resolvedDecoder)
  }

  /// Creates a new user.
  ///
  /// - To confirm the user's email address or phone number, set ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` to `true`. Both arguments default to `false`.
  /// - ``createUser(attributes:)`` will not send a confirmation email to the user. You can use ``inviteUserByEmail(_:data:redirectTo:)`` if you want to send them an email invite instead.
  /// - If you are sure that the created user's email or phone number is legitimate and verified, you can set the ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` param to true.
  /// - Warning: Never expose your `secret` key on the client.
  @discardableResult
  public func createUser(attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: configuration.url.appendingPathComponent("admin/users")
      ), body: encoder.encode(attributes)
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Sends an invite link to an email address.
  ///
  /// - Sends an invite link to the user's email address.
  /// - The ``inviteUserByEmail(_:data:redirectTo:)`` method is typically used by administrators to invite users to join the application.
  /// - Parameters:
  ///   - email: The email address of the user.
  ///   - data: A custom data object to store additional metadata about the user. This maps to the `auth.users.user_metadata` column.
  ///   - redirectTo: The URL which will be appended to the email link sent to the user's email address. Once clicked the user will end up on this URL.
  /// - Note: that PKCE is not supported when using ``inviteUserByEmail(_:data:redirectTo:)``. This is because the browser initiating the invite is often different from the browser accepting the invite which makes it difficult to provide the security guarantees required of the PKCE flow.
  @discardableResult
  public func inviteUserByEmail(
    _ email: String,
    data: [String: JSONValue]? = nil,
    redirectTo: URL? = nil
  ) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: configuration.url.appendingPathComponent("admin/invite"),
        query: [
          (redirectTo ?? configuration.redirectToURL).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 }
      ),
      body: encoder.encode(
        [
          "email": .string(email),
          "data": data.map({ JSONValue.object($0) }) ?? .null,
        ]
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Delete a user. Requires `secret` key.
  /// - Parameter id: The id of the user you want to delete.
  /// - Parameter shouldSoftDelete: If true, then the user will be soft-deleted (setting
  /// `deleted_at` to the current timestamp and disabling their account while preserving their data)
  /// from the auth schema.
  ///
  /// - Warning: Never expose your `secret` key on the client.
  public func deleteUser(id: UUID, shouldSoftDelete: Bool = false) async throws {
    _ = try await api.execute(
      HTTPRequest(
        method: .delete,
        url: configuration.url.appendingPathComponent("admin/users/\(id)")
      ),
      body: encoder.encode(
        DeleteUserRequest(shouldSoftDelete: shouldSoftDelete)
      )
    )
  }

  /// Signs out a user's session(s) using their access token.
  ///
  /// Unlike ``AuthClient/signOut(scope:)``, which signs out the *current* client's session, this
  /// lets a server holding another user's access token force that session (or all/other sessions
  /// for that user) to be revoked.
  ///
  /// - Parameters:
  ///   - jwt: The access token of the session(s) to sign out.
  ///   - scope: Specifies which sessions should be logged out.
  /// - Warning: Never expose your `secret` key on the client.
  public func signOut(jwt: String, scope: SignOutScope = .global) async throws {
    _ = try await api.execute(
      HTTPRequest(
        method: .post,
        url: configuration.url.appendingPathComponent("logout"),
        query: [URLQueryItem(name: "scope", value: scope.rawValue)],
        headerFields: [.authorization: "Bearer \(jwt)"]
      )
    )
  }

  /// Get a list of users.
  ///
  /// This function should only be called on a server.
  ///
  /// - Warning: Never expose your `secret` key in the client.
  public func listUsers(params: PageParams? = nil) async throws -> ListUsersPaginatedResponse {
    struct Response: Decodable {
      let users: [User]
      let aud: String
    }

    let (httpResponse, data) = try await api.send(
      HTTPRequest(
        method: .get,
        url: configuration.url.appendingPathComponent("admin/users"),
        query: [
          URLQueryItem(name: "page", value: params?.page?.description ?? ""),
          URLQueryItem(name: "per_page", value: params?.perPage?.description ?? ""),
        ]
      )
    )

    let response = try data.decoded(
      as: Response.self, decoder: configuration.resolvedDecoder)

    var pagination = ListUsersPaginatedResponse(
      users: response.users,
      aud: response.aud,
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

  /// Generates email links and OTPs to be sent via a custom email provider.
  ///
  /// - Parameter params: The parameters for the link generation.
  /// - Throws: An error if the link generation fails.
  /// - Returns: The generated link.
  public func generateLink(params: GenerateLinkParams) async throws -> GenerateLinkResponse {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: configuration.url.appendingPathComponent("admin/generate_link"),
        query: [
          (params.redirectTo ?? configuration.redirectToURL).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 }
      ), body: encoder.encode(params.body)
    ).decoded(decoder: configuration.resolvedDecoder)
  }
}

extension HTTPField.Name {
  static let xTotalCount = Self("x-total-count")!
  static let link = Self("link")!
}
