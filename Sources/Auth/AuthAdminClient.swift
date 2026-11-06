//
//  AuthAdminClient.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

public import Foundation
public import HTTPTypes
public import Helpers
public import Logging

/// A client for the Auth admin API, authenticated with the project's secret key.
///
/// It is separate from ``AuthClient`` on purpose. It never reads or writes a user session, and
/// it sends the secret key on every request, so build it only on a server:
///
/// ```swift
/// let admin = AuthAdminClient(
///   configuration: .init(
///     url: URL(string: "https://<project>.supabase.co/auth/v1")!,
///     secretKey: secretKey
///   )
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
/// - ``init(configuration:)``
/// - ``Configuration``
/// - ``configuration``
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
  /// The settings an ``AuthAdminClient`` is created with.
  public struct Configuration: Sendable {
    /// The base URL of the Auth server, such as `https://<project>.supabase.co/auth/v1`.
    public var url: URL

    /// The project's secret key. The client sends it as the `apikey` header. It also sends a
    /// legacy JWT key as the bearer token, but never an `sb_secret_` key.
    public var secretKey: String

    /// Headers sent with every request. A header set here wins over the `apikey` and
    /// `Authorization` headers the client derives from ``secretKey``.
    public var headers: HTTPFields

    /// The transport and middleware chain every request goes through.
    public var http: HTTPClientConfiguration

    /// The logger to use. Defaults to a build-config-aware logger. The client redacts secrets
    /// and tags it with the `system` metadata key set to `auth`.
    public var logger: Logging.Logger

    /// Whether to retry transient errors on `GET` requests. Defaults to `true`.
    public var retryEnabled: Bool

    /// The clock the retry backoff sleeps on. Defaults to `ContinuousClock()`.
    public var clock: any Clock<Duration>

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - secretKey: The project's secret key.
    ///   - headers: Headers sent with every request.
    ///   - http: The transport and middleware chain every request goes through.
    ///   - logger: The logger to use. Defaults to a build-config-aware logger.
    ///   - retryEnabled: Whether to retry transient errors on `GET` requests.
    ///   - clock: The clock the retry backoff sleeps on.
    public init(
      url: URL,
      secretKey: String,
      headers: HTTPFields = [:],
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      retryEnabled: Bool = true,
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self.url = url
      self.secretKey = secretKey
      self.headers = headers
      self.http = http
      self.logger = logger
      self.retryEnabled = retryEnabled
      self.clock = clock
    }
  }

  /// The configuration this client was created with.
  public let configuration: Configuration

  let authAPI: AuthAPI
  let api: APIClient

  /// Creates an admin client.
  ///
  /// - Parameter configuration: The settings the client is created with.
  public init(configuration: Configuration) {
    self.configuration = configuration

    var headers = AuthClient.Configuration.defaultHeaders
    headers[.apikeyHeaderName] = configuration.secretKey
    if !APIKeyFormat.isNew(configuration.secretKey) {
      headers[.authorization] = "Bearer \(configuration.secretKey)"
    }
    headers = headers.merging(with: configuration.headers)

    self.authAPI = AuthAPI(
      url: configuration.url,
      headers: headers,
      defaultRedirectURL: nil,
      encoder: AuthClient.Configuration.jsonEncoder,
      decoder: AuthClient.Configuration.jsonDecoder,
      now: { Date() }
    )
    var logger = configuration.logger.redactingSecrets()
    logger[metadataKey: "system"] = "auth"
    self.api = APIClient(
      http: HTTPClient(
        http: configuration.http,
        clock: configuration.clock,
        logger: logger,
        retryEnabled: configuration.retryEnabled
      ))
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

extension AuthAdminClient.Configuration: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// A description that shows `<redacted>` in place of ``secretKey`` and lists only the header
  /// names, so logs and crash reports never carry the key.
  public var description: String {
    "AuthAdminClient.Configuration(url: \(url), secretKey: <redacted>, headers: \(headerNames))"
  }

  /// The same text as ``description``.
  public var debugDescription: String { description }

  /// A mirror that shows `<redacted>` in place of ``secretKey`` and lists only the header names,
  /// so `dump(_:)` never prints the key.
  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "url": url,
        "secretKey": "<redacted>",
        "headers": headerNames,
        "http": http,
        "logger": logger,
        "retryEnabled": retryEnabled,
        "clock": clock,
      ],
      displayStyle: .struct
    )
  }

  private var headerNames: [String] { headers.map(\.name.rawName) }
}
