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
  /// Stamps the session of a response with the time the client received it.
  let now: @Sendable () -> Date

  init(
    url: URL,
    headers: HTTPFields,
    defaultRedirectURL: URL?,
    encoder: JSONEncoder,
    decoder: JSONDecoder,
    now: @escaping @Sendable () -> Date
  ) {
    var headers = headers
    if headers[.apiVersionHeaderName] == nil {
      headers[.apiVersionHeaderName] = Self.apiVersion
    }
    self.url = url
    self.headers = headers
    self.defaultRedirectURL = defaultRedirectURL
    self.encoder = encoder
    self.decoder = decoder
    self.now = now
  }
}

/// A request to GoTrue and how to read its response.
struct AuthRequest<Response>: Sendable {
  var head: HTTPRequest
  var body: Data?
  let decodeBody: @Sendable (HTTPResponse, Data) throws -> Response

  /// Whether a retry waits for a failure where the request never reached GoTrue. Every method
  /// but GET can change server state: `POST /token` rotates the refresh token, `/otp` sends a
  /// message. Replaying one after a timeout or a 5xx can repeat that change.
  var retriesOnlyConnectionFailures: Bool {
    head.method != .get
  }

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

  /// Encodes a request body as JSON.
  ///
  /// - Throws: ``AuthError`` with kind ``AuthError/Kind-swift.struct/invalidRequest`` when
  ///   `value` does not encode.
  func encodeBody(_ value: some Encodable) throws -> Data {
    do {
      return try encoder.encode(value)
    } catch {
      throw AuthError.invalidRequest(
        "The request body cannot be encoded as JSON.", underlyingError: error)
    }
  }

  func decodingSession() -> @Sendable (HTTPResponse, Data) throws -> Session {
    decoding(Session.self) { [now] in $0.received(at: now()) }
  }

  func decoding<T: Decodable>(_: T.Type) -> @Sendable (HTTPResponse, Data) throws -> T {
    { [decoder] _, data in try data.decoded(as: T.self, decoder: decoder) }
  }

  /// Decodes the body as `T`, then returns the part of it that `transform` picks.
  func decoding<T: Decodable, R>(
    _: T.Type, _ transform: @escaping @Sendable (T) -> R
  ) -> @Sendable (HTTPResponse, Data) throws -> R {
    { [decoder] _, data in try transform(data.decoded(as: T.self, decoder: decoder)) }
  }

  var ignoringBody: @Sendable (HTTPResponse, Data) throws -> Void {
    { _, _ in }
  }

  func bearer(_ accessToken: String) -> String {
    "Bearer \(accessToken)"
  }

  /// `redirect_to` as a query item, where GoTrue reads it on every endpoint except `/sso` and
  /// `POST /verify`, which read it from the body.
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
    userMetadata: JSONObject,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<SignUpResult> {
    try request(
      .post, "signup", query: redirectQuery(redirectTo),
      body: encodeBody(
        SignUpRequest(
          email: email,
          password: password,
          data: userMetadata.nilIfEmpty,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: decoding(SignUpResult.self) { [now] in $0.received(at: now()) }
    )
  }

  func signUp(
    phone: String,
    password: String,
    channel: MessagingChannel,
    userMetadata: JSONObject,
    captchaToken: String?
  ) throws -> AuthRequest<SignUpResult> {
    try request(
      .post, "signup",
      body: encodeBody(
        SignUpRequest(
          password: password,
          phone: phone,
          channel: channel,
          data: userMetadata.nilIfEmpty,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(SignUpResult.self) { [now] in $0.received(at: now()) }
    )
  }

  /// `POST /signup` with neither email nor phone, which the server treats as an anonymous
  /// sign-up. It always returns a session.
  func signInAnonymously(
    userMetadata: JSONObject,
    captchaToken: String?
  ) throws -> AuthRequest<Session> {
    try request(
      .post, "signup",
      body: encodeBody(
        SignUpRequest(
          data: userMetadata.nilIfEmpty,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decodingSession()
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
      body: encodeBody(
        UserCredentials(
          email: email,
          password: password,
          phone: phone,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decodingSession()
    )
  }

  /// `POST /token?grant_type=id_token`. Pass the user's access token to link the identity to
  /// that user instead of signing in.
  func signInWithIDToken(
    credentials: IDTokenCredentials,
    linkingTo accessToken: String? = nil
  ) throws -> AuthRequest<Session> {
    try token(
      grantType: "id_token",
      authorization: accessToken.map(bearer),
      body: encodeBody(
        IDTokenBody(
          provider: credentials.provider.rawValue,
          idToken: credentials.idToken,
          accessToken: credentials.accessToken,
          nonce: credentials.nonce,
          gotrueMetaSecurity: credentials.captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          linkIdentity: accessToken != nil
        )
      ),
      decode: decodingSession()
    )
  }

  func signInWithWeb3(credentials: Web3Credentials) throws -> AuthRequest<Session> {
    try token(
      grantType: "web3",
      body: encodeBody(
        Web3Body(
          chain: credentials.chain,
          message: credentials.message,
          signature: credentials.signature,
          gotrueMetaSecurity: credentials.captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decodingSession()
    )
  }

  func exchangeCodeForSession(
    authCode: String,
    codeVerifier: String
  ) throws -> AuthRequest<Session> {
    try token(
      grantType: "pkce",
      body: encodeBody(["auth_code": authCode, "code_verifier": codeVerifier]),
      decode: decodingSession()
    )
  }

  func refreshSession(refreshToken: String) throws -> AuthRequest<Session> {
    try token(
      grantType: "refresh_token",
      body: encodeBody(UserCredentials(refreshToken: refreshToken)),
      decode: decodingSession()
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
    options: EmailOTPOptions,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "otp", query: redirectQuery(options.redirectTo),
      body: encodeBody(
        OTPParams(
          email: email,
          createUser: options.shouldCreateUser,
          data: options.userMetadata.nilIfEmpty,
          gotrueMetaSecurity: options.captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod
        )
      ),
      decode: ignoringBody
    )
  }

  func signInWithOTP(phone: String, options: PhoneOTPOptions) throws -> AuthRequest<MessageID?> {
    try request(
      .post, "otp",
      body: encodeBody(
        OTPParams(
          phone: phone,
          createUser: options.shouldCreateUser,
          channel: options.channel,
          data: options.userMetadata.nilIfEmpty,
          gotrueMetaSecurity: options.captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(MessageIDBody.self) { $0.messageID }
    )
  }

  /// `POST /verify` checks no captcha token, so the verify requests send none.
  func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType
  ) throws -> AuthRequest<VerifyOTPResult> {
    try request(
      .post, "verify",
      body: encodeBody(
        VerifyOTPParams.email(VerifyEmailOTPParams(email: email, token: token, type: type))
      ),
      decode: decoding(VerifyOTPBody.self) { [now] in $0.result.received(at: now()) }
    )
  }

  func verifyOTP(
    phone: String,
    token: String,
    type: PhoneOTPType
  ) throws -> AuthRequest<Session> {
    try request(
      .post, "verify",
      body: encodeBody(
        VerifyOTPParams.phone(VerifyPhoneOTPParams(phone: phone, token: token, type: type))
      ),
      decode: decodingSession()
    )
  }

  func verifyOTP(tokenHash: String, type: EmailOTPType) throws -> AuthRequest<VerifyOTPResult> {
    try request(
      .post, "verify",
      body: encodeBody(
        VerifyOTPParams.tokenHash(VerifyTokenHashParams(tokenHash: tokenHash, type: type))
      ),
      decode: decoding(VerifyOTPBody.self) { [now] in $0.result.received(at: now()) }
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
      body: encodeBody(
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
    type: ResendPhoneType,
    captchaToken: String?
  ) throws -> AuthRequest<MessageID?> {
    try request(
      .post, "resend",
      body: encodeBody(
        ResendPhoneParams(
          type: type,
          phone: phone,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      ),
      decode: decoding(MessageIDBody.self) { $0.messageID }
    )
  }

  func resetPassword(
    email: String,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<Void> {
    try request(
      .post, "recover", query: redirectQuery(redirectTo),
      body: encodeBody(
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
    _ target: SSOTarget,
    redirectTo: URL?,
    captchaToken: String?,
    pkce: PKCEChallenge?
  ) throws -> AuthRequest<URL> {
    let (providerID, domain): (UUID?, String?) =
      switch target {
      case .domain(let domain): (nil, domain)
      case .providerID(let id): (id, nil)
      }
    return try request(
      .post, "sso",
      body: encodeBody(
        SignInWithSSORequest(
          providerID: providerID,
          domain: domain,
          redirectTo: redirectTo ?? defaultRedirectURL,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: pkce?.codeChallenge,
          codeChallengeMethod: pkce?.codeChallengeMethod,
          skipHttpRedirect: true
        )
      ),
      decode: decoding(URLBody.self) { $0.url }
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
    let url = try providerURL(
      url.appendingPathComponent("user/identities/authorize"), provider: provider, scopes: scopes,
      redirectTo: redirectTo, queryParams: queryParams, pkce: pkce, skipHTTPRedirect: true)

    return request(
      .get, url: url, authorization: bearer(accessToken),
      decode: decoding(URLBody.self) { $0.url })
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
      throw AuthError.invalidRequest(
        "The sign-in URL cannot be built from \(url).", underlyingError: URLError(.badURL))
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
      throw AuthError.invalidRequest(
        "The sign-in URL cannot be built from \(components).", underlyingError: URLError(.badURL))
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
    _ user: UpdateUser,
    redirectTo: URL?,
    pkce: PKCEChallenge?,
    accessToken: String
  ) throws -> AuthRequest<User> {
    var user = user
    user.userMetadata = user.userMetadata?.nilIfEmpty
    user.codeChallenge = pkce?.codeChallenge
    user.codeChallengeMethod = pkce?.codeChallengeMethod

    return try request(
      .put, "user", query: redirectQuery(redirectTo), authorization: bearer(accessToken),
      body: encodeBody(user), decode: decoding(User.self))
  }

  func unlinkIdentity(_ identity: UserIdentity, accessToken: String) -> AuthRequest<Void> {
    request(
      .delete, "user/identities/\(identity.id)", authorization: bearer(accessToken),
      decode: ignoringBody)
  }

  func jwks() -> AuthRequest<JWKS> {
    request(.get, ".well-known/jwks.json") { _, data in
      try data.decoded(as: JWKS.self, decoder: JSONDecoder())
    }
  }
}

// MARK: - OAuth 2.1 server

extension AuthAPI {
  func oauthAuthorizationDetails(
    id: String,
    accessToken: String
  ) -> AuthRequest<OAuthAuthorizationDetailsResult> {
    request(
      .get,
      url: url.appendingPathComponent("oauth/authorizations").appendingPathComponent(id),
      authorization: bearer(accessToken),
      decode: decoding(OAuthAuthorizationDetailsResult.self))
  }

  func oauthConsent(
    authorizationID: String,
    action: String,
    accessToken: String
  ) throws -> AuthRequest<OAuthRedirect> {
    try request(
      .post,
      url: url.appendingPathComponent("oauth/authorizations")
        .appendingPathComponent(authorizationID)
        .appendingPathComponent("consent"),
      authorization: bearer(accessToken),
      body: encodeBody(["action": action]), decode: decoding(OAuthRedirect.self))
  }

  func oauthGrants(accessToken: String) -> AuthRequest<[OAuthGrant]> {
    request(
      .get, "user/oauth/grants", authorization: bearer(accessToken),
      decode: decoding([OAuthGrant].self))
  }

  func revokeOAuthGrant(clientID: UUID, accessToken: String) -> AuthRequest<Void> {
    request(
      .delete, "user/oauth/grants",
      query: [URLQueryItem(name: "client_id", value: clientID.uuidString)],
      authorization: bearer(accessToken), decode: ignoringBody)
  }
}
