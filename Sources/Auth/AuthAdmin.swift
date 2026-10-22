//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

public import Foundation
import HTTPTypes
public import Helpers
public import Logging

/// Admin-only Auth operations that require the secret key.
///
/// Get one from ``AuthClient/admin``, or create one directly with
/// ``init(url:headers:redirectToURL:http:logger:)`` on a server that has no user session. It
/// carries its own transport and never reads or writes a session.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app — call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Creating an admin client
/// - ``init(url:headers:redirectToURL:http:logger:)``
///
/// ### User management
/// - ``user(id:)``
/// - ``updateUserById(_:attributes:)``
/// - ``createUser(attributes:)``
/// - ``inviteUserByEmail(_:data:redirectTo:)``
/// - ``deleteUser(id:shouldSoftDelete:)``
/// - ``listUsers(params:)``
/// - ``users(perPage:)``
/// - ``generateLink(params:)``
/// - ``signOut(jwt:scope:)``
///
/// ### OAuth 2.1 clients
/// - ``oauth``
///
/// ### Multi-factor authentication
/// - ``mfa``
public struct AuthAdmin: Sendable {
  let url: URL
  /// Default redirect for the flows that take one, when the caller passes none.
  let redirectToURL: URL?
  let api: APIClient
  let encoder: JSONEncoder
  let decoder: JSONDecoder

  /// Contains all OAuth client administration methods.
  /// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
  ///
  /// - Warning: This property requires `secret` key. Be careful to never expose your `secret` key in the browser.
  public var oauth: AuthAdminOAuth {
    AuthAdminOAuth(admin: self)
  }

  /// Contains all multi-factor authentication administration methods.
  ///
  /// - Warning: This property requires `secret` key. Be careful to never expose your `secret` key in the browser.
  public var mfa: AuthAdminMFA {
    AuthAdminMFA(admin: self)
  }

  /// Get user by id.
  /// - Parameter id: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the browser.
  public func user(id: UUID) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: url.appendingPathComponent("admin/users/\(id)")
      )
    ).decoded(decoder: decoder)
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
        url: url.appendingPathComponent("admin/users/\(uid)")
      ), body: encoder.encode(attributes)
    ).decoded(decoder: decoder)
  }

  /// Creates a new user.
  ///
  /// - To confirm the user's email address or phone number, set ``AdminUserAttributes/confirmsEmail`` or ``AdminUserAttributes/confirmsPhone`` to `true`. Both arguments default to `false`.
  /// - ``createUser(attributes:)`` will not send a confirmation email to the user. You can use ``inviteUserByEmail(_:data:redirectTo:)`` if you want to send them an email invite instead.
  /// - If you are sure that the created user's email or phone number is legitimate and verified, you can set the ``AdminUserAttributes/confirmsEmail`` or ``AdminUserAttributes/confirmsPhone`` param to true.
  /// - Warning: Never expose your `secret` key on the client.
  @discardableResult
  public func createUser(attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: url.appendingPathComponent("admin/users")
      ), body: encoder.encode(attributes)
    )
    .decoded(decoder: decoder)
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
        url: url.appendingPathComponent("invite"),
        query: [
          (redirectTo ?? redirectToURL).map {
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
    .decoded(decoder: decoder)
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
        url: url.appendingPathComponent("admin/users/\(id)")
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
        url: url.appendingPathComponent("logout"),
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
        url: url.appendingPathComponent("admin/users"),
        query: [
          params?.page.map { URLQueryItem(name: "page", value: $0.description) },
          params?.perPage.map { URLQueryItem(name: "per_page", value: $0.description) },
        ].compactMap { $0 }
      )
    )

    let response = try data.decoded(
      as: Response.self, decoder: decoder)

    var pagination = ListUsersPaginatedResponse(
      users: response.users,
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

  /// Generates email links and OTPs to be sent via a custom email provider.
  ///
  /// - Parameter params: The parameters for the link generation.
  /// - Throws: An error if the link generation fails.
  /// - Returns: The generated link.
  public func generateLink(params: GenerateLinkParams) async throws -> GenerateLinkResponse {
    try await api.execute(
      HTTPRequest(
        method: .post,
        url: url.appendingPathComponent("admin/generate_link"),
        query: [
          (params.redirectTo ?? redirectToURL).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 }
      ), body: encoder.encode(params.body)
    ).decoded(decoder: decoder)
  }
}

extension HTTPField.Name {
  static let xTotalCount = Self("x-total-count")!
  static let link = Self("link")!
}

extension AuthAdmin {
  /// Creates an admin client that talks to the Auth server on its own, with no user session.
  ///
  /// Use this on a server where nobody is signed in, the same way supabase-js exposes
  /// `GoTrueAdminApi`. When you already have an ``AuthClient``, ``AuthClient/admin`` builds one
  /// from its configuration instead.
  ///
  /// ```swift
  /// let admin = AuthAdmin(
  ///   url: URL(string: "https://<project>.supabase.co/auth/v1")!,
  ///   headers: [
  ///     "apikey": secretKey,
  ///     "Authorization": "Bearer \(secretKey)",
  ///   ]
  /// )
  /// let users = try await admin.listUsers()
  /// ```
  ///
  /// > Warning: The secret key grants full access to your project's users. Never ship it in a
  /// > client app.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server, such as `https://<project>.supabase.co/auth/v1`.
  ///   - headers: Headers sent with every request. Include `apikey` and an
  ///     `Authorization: Bearer <secret key>` header.
  ///   - redirectToURL: Default redirect for ``inviteUserByEmail(_:data:redirectTo:)`` and
  ///     ``generateLink(params:)`` when the call passes none.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - logger: The logger to use. Defaults to a build-config-aware logger.
  public init(
    url: URL,
    headers: [String: String] = [:],
    redirectToURL: URL? = nil,
    http: HTTPClientConfiguration = .init(),
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth")
  ) {
    self.init(
      url: url,
      redirectToURL: redirectToURL,
      api: APIClient(
        headers: headers,
        http: HTTPClient(http: http, clock: ContinuousClock(), logger: logger),
        decoder: AuthClient.Configuration.jsonDecoder
      ),
      encoder: AuthClient.Configuration.jsonEncoder,
      decoder: AuthClient.Configuration.jsonDecoder
    )
  }
}
