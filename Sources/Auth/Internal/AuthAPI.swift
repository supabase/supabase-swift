//
//  AuthAPI.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes

/// Builds every request the SDK sends to GoTrue and decodes every response.
///
/// Pure: each endpoint maps its inputs to an ``AuthRequest``, and the request maps the response
/// to a model. Nothing here reads the session, touches storage, or emits events; the clients that
/// send the requests own that. Field spellings follow the server, not the public API: `create_user`,
/// `gotrue_meta_security.captcha_token`, and `redirect_to` in the query string except where the
/// server reads it from the body.
struct AuthAPI: Sendable {
  /// The value of `X-Supabase-Api-Version`. It selects the error body shape
  /// `{"code": "<error_code>", "message": "…"}`.
  static let apiVersion = "2024-01-01"

  let url: URL
  /// Sent with every request: the configured headers (`apikey` among them) and the API version.
  let headers: HTTPFields
  /// The redirect used when a call does not pass its own.
  let defaultRedirectURL: URL?
  let encoder: JSONEncoder
  let decoder: JSONDecoder

  init(
    url: URL,
    headers: [String: String],
    defaultRedirectURL: URL?,
    encoder: JSONEncoder,
    decoder: JSONDecoder
  ) {
    var headers = HTTPFields(headers)
    if headers[.apiVersionHeaderName] == nil {
      headers[.apiVersionHeaderName] = Self.apiVersion
    }
    self.url = url
    self.headers = headers
    self.defaultRedirectURL = defaultRedirectURL
    self.encoder = encoder
    self.decoder = decoder
  }
}

/// A request to GoTrue and how to read its response.
struct AuthRequest<Response>: Sendable {
  var head: HTTPRequest
  var body: Data?
  let decodeBody: @Sendable (HTTPResponse, Data) throws -> Response

  /// The model for a response to this request, or the ``AuthError`` from ``ErrorDecoder`` when
  /// the status is not 2xx.
  func decode(_ response: HTTPResponse, _ data: Data) throws -> Response {
    if let error = ErrorDecoder.error(response: response, data: data, request: head) {
      throw error
    }
    return try decodeBody(response, data)
  }
}

/// The PKCE challenge sent when a flow starts. The verifier stays on the device.
struct PKCEChallenge: Sendable, Hashable {
  let codeChallenge: String
  let codeChallengeMethod: String
}

extension AuthAPI {
  func request<Response>(
    _ method: HTTPRequest.Method,
    _ path: String,
    query: [URLQueryItem] = [],
    authorization: String? = nil,
    body: Data? = nil,
    decode: @escaping @Sendable (HTTPResponse, Data) throws -> Response
  ) -> AuthRequest<Response> {
    request(
      method, url: url.appendingPathComponent(path), query: query, authorization: authorization,
      body: body, decode: decode)
  }

  func request<Response>(
    _ method: HTTPRequest.Method,
    url: URL,
    query: [URLQueryItem] = [],
    authorization: String? = nil,
    body: Data? = nil,
    decode: @escaping @Sendable (HTTPResponse, Data) throws -> Response
  ) -> AuthRequest<Response> {
    var head = HTTPRequest(method: method, url: url, query: query, headerFields: headers)
    if let authorization {
      head.headerFields[.authorization] = authorization
    }
    return AuthRequest(head: head, body: body, decodeBody: decode)
  }

  func decoding<T: Decodable>(_: T.Type) -> @Sendable (HTTPResponse, Data) throws -> T {
    { [decoder] _, data in try data.decoded(as: T.self, decoder: decoder) }
  }

  var ignoringBody: @Sendable (HTTPResponse, Data) throws -> Void {
    { _, _ in }
  }

  func bearer(_ accessToken: String) -> String {
    "Bearer \(accessToken)"
  }

  /// `redirect_to` as a query item, where GoTrue reads it on every endpoint except `/sso`.
  func redirectQuery(_ redirectTo: URL?) -> [URLQueryItem] {
    guard let redirectTo = redirectTo ?? defaultRedirectURL else { return [] }
    return [URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString)]
  }

  func token<Response>(
    grantType: String,
    authorization: String? = nil,
    body: Data,
    decode: @escaping @Sendable (HTTPResponse, Data) throws -> Response
  ) -> AuthRequest<Response> {
    request(
      .post, "token", query: [URLQueryItem(name: "grant_type", value: grantType)],
      authorization: authorization, body: body, decode: decode)
  }
}

// MARK: - Sign-up and sign-in

extension AuthAPI {
  func signUp(
    email: String,
    password: String,
    data: [String: JSONValue]?,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<AuthResponse> {
    try request(
      .post, "signup", query: redirectQuery(redirectTo),
      body: encoder.encode(
        SignUpRequest(
          email: email,
          password: password,
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: decoding(AuthResponse.self)
    )
  }

  func signUp(
    phone: String,
    password: String,
    channel: MessagingChannel,
    data: [String: JSONValue]?,
    captchaToken: String?
  ) throws -> AuthRequest<AuthResponse> {
    try request(
      .post, "signup",
      body: encoder.encode(
        SignUpRequest(
          password: password,
          phone: phone,
          channel: channel,
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(AuthResponse.self)
    )
  }

  /// `POST /signup` with neither email nor phone, which the server treats as an anonymous
  /// sign-up. It always returns a session.
  func signInAnonymously(
    data: [String: JSONValue]?,
    captchaToken: String?
  ) throws -> AuthRequest<Session> {
    try request(
      .post, "signup",
      body: encoder.encode(
        SignUpRequest(
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(Session.self)
    )
  }

  func signInWithPassword(
    email: String? = nil,
    phone: String? = nil,
    password: String,
    captchaToken: String?
  ) throws -> AuthRequest<Session> {
    try token(
      grantType: "password",
      body: encoder.encode(
        UserCredentials(
          email: email,
          password: password,
          phone: phone,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(Session.self)
    )
  }

  /// `POST /token?grant_type=id_token`. Pass the user's access token to link the identity to
  /// that user instead of signing in.
  func signInWithIdToken(
    credentials: OpenIDConnectCredentials,
    linkingTo accessToken: String? = nil
  ) throws -> AuthRequest<Session> {
    try token(
      grantType: "id_token",
      authorization: accessToken.map(bearer),
      body: encoder.encode(credentials),
      decode: decoding(Session.self)
    )
  }

  func signInWithWeb3(credentials: Web3Credentials) throws -> AuthRequest<Session> {
    try token(
      grantType: "web3", body: encoder.encode(credentials), decode: decoding(Session.self))
  }

  func exchangeCodeForSession(
    authCode: String,
    codeVerifier: String?
  ) throws -> AuthRequest<Session> {
    try token(
      grantType: "pkce",
      body: encoder.encode(["auth_code": authCode, "code_verifier": codeVerifier]),
      decode: decoding(Session.self)
    )
  }

  func refreshSession(refreshToken: String) throws -> AuthRequest<Session> {
    try token(
      grantType: "refresh_token",
      body: encoder.encode(UserCredentials(refreshToken: refreshToken)),
      decode: decoding(Session.self)
    )
  }

  func signOut(accessToken: String, scope: SignOutScope) -> AuthRequest<Void> {
    request(
      .post, "logout", query: [URLQueryItem(name: "scope", value: scope.rawValue)],
      authorization: bearer(accessToken), decode: ignoringBody)
  }
}

// MARK: - OTP, magic link, and verification

extension AuthAPI {
  func signInWithOTP(
    email: String,
    redirectTo: URL?,
    shouldCreateUser: Bool,
    data: [String: JSONValue]?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "otp", query: redirectQuery(redirectTo),
      body: encoder.encode(
        OTPParams(
          email: email,
          createUser: shouldCreateUser,
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: ignoringBody
    )
  }

  func signInWithOTP(
    phone: String,
    channel: MessagingChannel,
    shouldCreateUser: Bool,
    data: [String: JSONValue]?,
    captchaToken: String?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "otp",
      body: encoder.encode(
        OTPParams(
          phone: phone,
          createUser: shouldCreateUser,
          channel: channel,
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: ignoringBody
    )
  }

  func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType,
    redirectTo: URL?,
    captchaToken: String?
  ) throws -> AuthRequest<VerifyOTPResponse> {
    try request(
      .post, "verify", query: redirectQuery(redirectTo),
      body: encoder.encode(
        VerifyOTPParams.email(
          VerifyEmailOTPParams(
            email: email,
            token: token,
            type: type,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      ),
      decode: decoding(VerifyOTPResponse.self)
    )
  }

  func verifyOTP(
    phone: String,
    token: String,
    type: MobileOTPType,
    captchaToken: String?
  ) throws -> AuthRequest<VerifyOTPResponse> {
    try request(
      .post, "verify",
      body: encoder.encode(
        VerifyOTPParams.mobile(
          VerifyMobileOTPParams(
            phone: phone,
            token: token,
            type: type,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      ),
      decode: decoding(VerifyOTPResponse.self)
    )
  }

  func verifyOTP(tokenHash: String, type: EmailOTPType) throws -> AuthRequest<VerifyOTPResponse> {
    try request(
      .post, "verify",
      body: encoder.encode(
        VerifyOTPParams.tokenHash(VerifyTokenHashParams(tokenHash: tokenHash, type: type))
      ),
      decode: decoding(VerifyOTPResponse.self)
    )
  }

  func resend(
    email: String,
    type: ResendEmailType,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "resend", query: redirectQuery(redirectTo),
      body: encoder.encode(
        ResendEmailParams(
          type: type,
          email: email,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: ignoringBody
    )
  }

  func resend(
    phone: String,
    type: ResendMobileType,
    captchaToken: String?
  ) throws -> AuthRequest<ResendMobileResponse> {
    try request(
      .post, "resend",
      body: encoder.encode(
        ResendMobileParams(
          type: type,
          phone: phone,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(ResendMobileResponse.self)
    )
  }

  func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "recover", query: redirectQuery(redirectTo),
      body: encoder.encode(
        RecoverParams(
          email: email,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: ignoringBody
    )
  }

  func reauthenticate(accessToken: String) -> AuthRequest<Void> {
    request(.get, "reauthenticate", authorization: bearer(accessToken), decode: ignoringBody)
  }
}

// MARK: - SSO and OAuth

extension AuthAPI {
  /// `POST /sso`. Unlike every other endpoint, GoTrue reads `redirect_to` and
  /// `skip_http_redirect` from the body here.
  func signInWithSSO(
    providerId: String? = nil,
    domain: String? = nil,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<SSOResponse> {
    try request(
      .post, "sso",
      body: encoder.encode(
        SignInWithSSORequest(
          providerId: providerId,
          domain: domain,
          redirectTo: redirectTo ?? defaultRedirectURL,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod,
          skipHttpRedirect: true
        )
      ),
      decode: decoding(SSOResponse.self)
    )
  }

  /// The `/authorize` URL the browser opens to start an OAuth flow.
  ///
  /// A browser URL, not an API request: it carries neither `apikey` nor the API version header.
  func authorizeURL(
    provider: Provider,
    scopes: String?,
    redirectTo: URL?,
    queryParams: [(name: String, value: String?)],
    pkce: PKCEChallenge?
  ) throws -> URL {
    try providerURL(
      url.appendingPathComponent("authorize"), provider: provider, scopes: scopes,
      redirectTo: redirectTo, queryParams: queryParams, pkce: pkce, skipHTTPRedirect: false)
  }

  /// `GET /user/identities/authorize` with `skip_http_redirect=true` in the query, so the server
  /// answers with the provider URL instead of a 302.
  func linkIdentityURL(
    provider: Provider,
    scopes: String?,
    redirectTo: URL?,
    queryParams: [(name: String, value: String?)],
    pkce: PKCEChallenge?,
    accessToken: String
  ) throws -> AuthRequest<URL> {
    struct Response: Decodable {
      let url: URL
    }

    let url = try providerURL(
      url.appendingPathComponent("user/identities/authorize"), provider: provider, scopes: scopes,
      redirectTo: redirectTo, queryParams: queryParams, pkce: pkce, skipHTTPRedirect: true)

    return request(
      .get, url: url, authorization: bearer(accessToken),
      decode: { [decoder] _, data in try data.decoded(as: Response.self, decoder: decoder).url })
  }

  private func providerURL(
    _ url: URL,
    provider: Provider,
    scopes: String?,
    redirectTo: URL?,
    queryParams: [(name: String, value: String?)],
    pkce: PKCEChallenge?,
    skipHTTPRedirect: Bool
  ) throws -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }

    var queryItems = [URLQueryItem(name: "provider", value: provider.rawValue)]

    if let scopes {
      queryItems.append(URLQueryItem(name: "scopes", value: scopes))
    }

    if let redirectTo = redirectTo ?? defaultRedirectURL {
      queryItems.append(URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString))
    }

    if let pkce {
      queryItems.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
      queryItems.append(
        URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod))
    }

    if skipHTTPRedirect {
      queryItems.append(URLQueryItem(name: "skip_http_redirect", value: "true"))
    }

    queryItems.append(contentsOf: queryParams.map(URLQueryItem.init))

    components.queryItems = queryItems

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return url
  }
}

// MARK: - User and identities

extension AuthAPI {
  /// `GET /user`. `tokenType` is the scheme the token was issued with; a token read from a
  /// redirect URL carries its own (`bearer`).
  func user(accessToken: String, tokenType: String = "Bearer") -> AuthRequest<User> {
    request(.get, "user", authorization: "\(tokenType) \(accessToken)", decode: decoding(User.self))
  }

  func updateUser(
    _ user: UserAttributes,
    redirectTo: URL?,
    pkce: PKCEChallenge?,
    accessToken: String
  ) throws -> AuthRequest<User> {
    var user = user
    user.codeChallenge = pkce?.codeChallenge
    user.codeChallengeMethod = pkce?.codeChallengeMethod

    return try request(
      .put, "user", query: redirectQuery(redirectTo), authorization: bearer(accessToken),
      body: encoder.encode(user), decode: decoding(User.self))
  }

  func unlinkIdentity(_ identity: UserIdentity, accessToken: String) -> AuthRequest<Void> {
    request(
      .delete, "user/identities/\(identity.identityId)", authorization: bearer(accessToken),
      decode: ignoringBody)
  }

  func jwks() -> AuthRequest<JWKS> {
    request(.get, ".well-known/jwks.json", decode: decoding(JWKS.self))
  }
}

// MARK: - OAuth 2.1 server

extension AuthAPI {
  func oauthAuthorizationDetails(
    id: String,
    accessToken: String
  ) -> AuthRequest<OAuthAuthorizationDetailsResponse> {
    request(
      .get,
      url: url.appendingPathComponent("oauth/authorizations").appendingPathComponent(id),
      authorization: bearer(accessToken),
      decode: decoding(OAuthAuthorizationDetailsResponse.self))
  }

  func oauthConsent(
    authorizationId: String,
    action: String,
    accessToken: String
  ) throws -> AuthRequest<OAuthRedirect> {
    try request(
      .post,
      url: url.appendingPathComponent("oauth/authorizations")
        .appendingPathComponent(authorizationId)
        .appendingPathComponent("consent"),
      authorization: bearer(accessToken),
      body: encoder.encode(["action": action]), decode: decoding(OAuthRedirect.self))
  }

  func oauthGrants(accessToken: String) -> AuthRequest<[OAuthGrant]> {
    request(
      .get, "user/oauth/grants", authorization: bearer(accessToken),
      decode: decoding([OAuthGrant].self))
  }

  func revokeOAuthGrant(clientId: UUID, accessToken: String) -> AuthRequest<Void> {
    request(
      .delete, "user/oauth/grants",
      query: [URLQueryItem(name: "client_id", value: clientId.uuidString)],
      authorization: bearer(accessToken), decode: ignoringBody)
  }
}
