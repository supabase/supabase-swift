//
//  AuthAdminClient.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

public import Foundation
public import Helpers
public import Logging

/// A client for the Auth admin API, authenticated with the project's secret key.
///
/// It is separate from ``AuthClient`` on purpose. It never reads or writes a user session, and
/// it sends the secret key on every request, so build it only on a server:
///
/// ```swift
/// let admin = AuthAdminClient(
///   url: URL(string: "https://<project>.supabase.co/auth/v1")!,
///   secretKey: secretKey
/// )
/// let user = try await admin.createUser(
///   AdminUserAttributes(email: "user@example.com", confirmsEmail: true)
/// )
/// ```
///
/// > Warning: The secret key grants full access to your project's users. Never ship it in a
/// > browser or mobile app.
///
/// ## Topics
///
/// ### Creating an admin client
/// - ``init(url:secretKey:http:logger:)``
///
/// ### User management
/// - ``user(id:)``
/// - ``createUser(_:)``
/// - ``updateUser(id:attributes:)``
/// - ``deleteUser(id:softDelete:)``
/// - ``inviteUser(email:userMetadata:redirectTo:)``
/// - ``listUsers(page:pageSize:)``
/// - ``users(pageSize:)``
/// - ``generateLink(_:)``
/// - ``signOut(jwt:scope:)``
///
/// ### Namespaces
/// - ``mfa``
/// - ``oauth``
/// - ``customProviders``
public struct AuthAdminClient: Sendable {
  let authAPI: AuthAPI
  let api: APIClient

  /// Creates an admin client.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server, such as `https://<project>.supabase.co/auth/v1`.
  ///   - secretKey: The project's secret key. The client sends it as the `apikey` header. It
  ///     also sends a legacy JWT key as the bearer token, but never an `sb_secret_` key.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - logger: The logger to use. Defaults to a build-config-aware logger.
  public init(
    url: URL,
    secretKey: String,
    http: HTTPClientConfiguration = .init(),
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth")
  ) {
    var headers = AuthClient.Configuration.defaultHeaders
    headers[.apikeyHeaderName] = secretKey
    if !APIKeyFormat.isNew(secretKey) {
      headers[.authorization] = "Bearer \(secretKey)"
    }

    self.authAPI = AuthAPI(
      url: url,
      headers: headers,
      defaultRedirectURL: nil,
      encoder: AuthClient.Configuration.jsonEncoder,
      decoder: AuthClient.Configuration.jsonDecoder,
      now: { Date() }
    )
    var logger = logger.redactingSecrets()
    logger[metadataKey: "system"] = "auth"
    self.api = APIClient(http: HTTPClient(http: http, clock: ContinuousClock(), logger: logger))
  }

  /// Admin operations on a user's MFA factors.
  public var mfa: AuthAdminMFA {
    AuthAdminMFA(admin: self)
  }

  /// Admin operations on OAuth 2.1 clients. Only relevant when the OAuth 2.1 server is enabled
  /// in Supabase Auth.
  public var oauth: AuthAdminOAuth {
    AuthAdminOAuth(admin: self)
  }

  /// Admin operations on custom OAuth 2.0 and OIDC providers.
  public var customProviders: AuthAdminCustomProviders {
    AuthAdminCustomProviders(admin: self)
  }

  /// Gets a user.
  ///
  /// - Parameter id: The user's unique identifier.
  public func user(id: UUID) async throws -> User {
    try await api.execute(authAPI.adminUser(id: id))
  }

  /// Creates a user.
  ///
  /// The server sends no confirmation email. Set ``AdminUserAttributes/confirmsEmail`` or
  /// ``AdminUserAttributes/confirmsPhone`` to `true` to mark the address as confirmed. To email
  /// the user an invite instead, use ``inviteUser(email:userMetadata:redirectTo:)``.
  ///
  /// - Parameter attributes: The attributes of the new user.
  @discardableResult
  public func createUser(_ attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(authAPI.adminCreateUser(attributes: attributes))
  }

  /// Updates a user. The server changes only the attributes you set.
  ///
  /// - Parameters:
  ///   - id: The user's unique identifier.
  ///   - attributes: The attributes to change.
  @discardableResult
  public func updateUser(id: UUID, attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(authAPI.adminUpdateUser(id: id, attributes: attributes))
  }

  /// Deletes a user.
  ///
  /// - Parameters:
  ///   - id: The user's unique identifier.
  ///   - softDelete: When `true`, the server sets `deleted_at` and disables the account but
  ///     keeps its data. When `false`, the server removes the user.
  public func deleteUser(id: UUID, softDelete: Bool = false) async throws {
    try await api.execute(authAPI.adminDeleteUser(id: id, softDelete: softDelete))
  }

  /// Emails an invite link to a new user.
  ///
  /// PKCE does not apply to invites. The browser that accepts the invite is often not the one
  /// that sent it.
  ///
  /// - Parameters:
  ///   - email: The email address to invite.
  ///   - userMetadata: Metadata to store in the user's `user_metadata`.
  ///   - redirectTo: The URL the invite link sends the user to.
  @discardableResult
  public func inviteUser(
    email: String,
    userMetadata: JSONObject = [:],
    redirectTo: URL? = nil
  ) async throws -> User {
    try await api.execute(
      authAPI.adminInviteUser(email: email, userMetadata: userMetadata, redirectTo: redirectTo))
  }

  /// Gets one page of users.
  ///
  /// To walk every page, use ``users(pageSize:)``.
  ///
  /// - Parameters:
  ///   - page: The page to get, starting at `1`. `nil` gets the first page.
  ///   - pageSize: Users per page. `nil` leaves the page size to the server.
  public func listUsers(page: Int? = nil, pageSize: Int? = nil) async throws -> UserPage {
    try await api.execute(authAPI.adminListUsers(page: page, pageSize: pageSize))
  }

  /// Generates an email link and OTP for you to send through your own email provider.
  ///
  /// - Parameter params: The kind of link and its options.
  public func generateLink(_ params: GenerateLinkParams) async throws -> GenerateLinkResponse {
    try await api.execute(authAPI.adminGenerateLink(params: params))
  }

  /// Signs out the session that owns an access token.
  ///
  /// Unlike ``AuthClient/signOut(scope:)``, which signs out the client's own session, this lets
  /// a server that holds a user's access token revoke that user's sessions.
  ///
  /// - Parameters:
  ///   - jwt: The access token of the session to sign out.
  ///   - scope: Which of the user's sessions to sign out.
  public func signOut(jwt: String, scope: SignOutScope = .global) async throws {
    try await api.execute(authAPI.signOut(accessToken: jwt, scope: scope))
  }
}
