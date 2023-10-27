import Foundation
@_spi(Internal) import _Helpers

public typealias AnyJSON = _Helpers.AnyJSON

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor GoTrueClient {
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

  public struct Configuration: Sendable {
    public let url: URL
    public var headers: [String: String]
    public let flowType: AuthFlowType
    public let localStorage: GoTrueLocalStorage
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let fetch: FetchHandler

    public init(
      url: URL,
      headers: [String: String] = [:],
      flowType: AuthFlowType = .implicit,
      localStorage: GoTrueLocalStorage? = nil,
      encoder: JSONEncoder = .goTrue,
      decoder: JSONDecoder = .goTrue,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
    ) {
      var headers = headers
      if headers["X-Client-Info"] == nil {
        headers["X-Client-Info"] = "gotrue-swift/\(version)"
      }

      self.url = url
      self.headers = headers
      self.flowType = flowType
      self.localStorage =
        localStorage
        ?? KeychainLocalStorage(
          service: "supabase.gotrue.swift",
          accessGroup: nil
        )
      self.encoder = encoder
      self.decoder = decoder
      self.fetch = fetch
    }
  }

  private var configuration: Configuration {
    Dependencies.current.value!.configuration
  }

  private var api: APIClient {
    Dependencies.current.value!.api
  }

  private var sessionManager: SessionManager {
    Dependencies.current.value!.sessionManager
  }

  private let codeVerifierStorage: CodeVerifierStorage

  private var eventEmitter: EventEmitter {
    Dependencies.current.value!.eventEmitter
  }

  /// Returns the session, refreshing it if necessary.
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Namespace for accessing multi-factor authentication API.
  public let mfa: GoTrueMFA

  public init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = .implicit,
    localStorage: GoTrueLocalStorage? = nil,
    encoder: JSONEncoder = .goTrue,
    decoder: JSONDecoder = .goTrue,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        localStorage: localStorage,
        encoder: encoder,
        decoder: decoder,
        fetch: fetch
      )
    )
  }

  public init(configuration: Configuration) {
    let sessionManager = DefaultSessionManager()

    let codeVerifierStorage = DefaultCodeVerifierStorage()
    let api = APIClient()

    self.init(
      configuration: configuration,
      sessionManager: sessionManager,
      codeVerifierStorage: codeVerifierStorage,
      api: api,
      eventEmitter: .live,
      sessionStorage: .live
    )
  }

  /// This internal initializer is here only for easy injecting mock instances when testing.
  init(
    configuration: Configuration,
    sessionManager: SessionManager,
    codeVerifierStorage: CodeVerifierStorage,
    api: APIClient,
    eventEmitter: EventEmitter,
    sessionStorage: SessionStorage
  ) {
    self.codeVerifierStorage = codeVerifierStorage
    self.mfa = GoTrueMFA()

    Dependencies.current.setValue(
      Dependencies(
        configuration: configuration,
        sessionManager: sessionManager,
        api: api,
        eventEmitter: eventEmitter,
        sessionStorage: sessionStorage,
        sessionRefresher: SessionRefresher(
          refreshSession: { [weak self] in
            try await self?.refreshSession(refreshToken: $0) ?? .empty
          }
        )
      )
    )
  }

  public func onAuthStateChange() async -> AsyncStream<AuthChangeEvent> {
    let (id, stream) = await eventEmitter.attachListener()

    Task { [id] in
      _debug("emitInitialSessionTask start")
      defer { _debug("emitInitialSessionTask end") }
      await emitInitialSession(forStreamWithID: id)
    }

    return stream
  }

  /// Creates a new user.
  /// - Parameters:
  ///   - email: User's email address.
  ///   - password: Password for the user.
  ///   - data: User's metadata.
  @discardableResult
  public func signUp(
    email: String,
    password: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await _signUp(
      request: .init(
        path: "/signup",
        method: "POST",
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) }
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          SignUpRequest(
            email: email,
            password: password,
            data: data,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
  }

  private func prepareForPKCE() -> (codeChallenge: String?, codeChallengeMethod: String?) {
    if configuration.flowType == .pkce {
      let codeVerifier = PKCE.generateCodeVerifier()

      do {
        try codeVerifierStorage.storeCodeVerifier(codeVerifier)
      } catch {
        _debug("Error storing code verifier: \(error)")
      }

      let codeChallenge = PKCE.generateCodeChallenge(from: codeVerifier)
      let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

      return (codeChallenge, codeChallengeMethod)
    }

    return (nil, nil)
  }

  /// Creates a new user.
  /// - Parameters:
  ///   - phone: User's phone number with international prefix.
  ///   - password: Password for the user.
  ///   - data: User's metadata.
  @discardableResult
  public func signUp(
    phone: String,
    password: String,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _signUp(
      request: .init(
        path: "/signup",
        method: "POST",
        body: configuration.encoder.encode(
          SignUpRequest(
            password: password,
            phone: phone,
            data: data,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  private func _signUp(request: Request) async throws -> AuthResponse {
    await sessionManager.remove()
    let response = try await api.execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.decoder
    )

    if let session = response.session {
      try await sessionManager.update(session)
      await eventEmitter.emit(.signedIn)
    }

    return response
  }

  /// Log in an existing user with an email and password.
  @discardableResult
  public func signIn(email: String, password: String) async throws -> Session {
    try await _signIn(
      request: .init(
        path: "/token",
        method: "POST",
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.encoder.encode(
          UserCredentials(email: email, password: password)
        )
      )
    )
  }

  /// Log in an existing user with a phone and password.
  @discardableResult
  public func signIn(phone: String, password: String) async throws -> Session {
    try await _signIn(
      request: .init(
        path: "/token",
        method: "POST",
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.encoder.encode(
          UserCredentials(password: password, phone: phone)
        )
      )
    )
  }

  /// Allows signing in with an ID token issued by certain supported providers.
  /// The ID token is verified for validity and a new session is established.
  @discardableResult
  public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session {
    try await _signIn(
      request: .init(
        path: "/token",
        method: "POST",
        query: [URLQueryItem(name: "grant_type", value: "id_token")],
        body: configuration.encoder.encode(credentials)
      )
    )
  }

  private func _signIn(request: Request) async throws -> Session {
    await sessionManager.remove()

    let session = try await api.execute(request).decoded(
      as: Session.self,
      decoder: configuration.decoder
    )

    if session.user.emailConfirmedAt != nil || session.user.confirmedAt != nil {
      try await sessionManager.update(session)
      await eventEmitter.emit(.signedIn)
    }

    return session
  }

  /// Log in user using magic link.
  ///
  /// If the `{{ .ConfirmationURL }}` variable is specified in the email template, a magic link will
  /// be sent.
  /// If the `{{ .Token }}` variable is specified in the email template, an OTP will be sent.
  /// - Parameters:
  ///   - email: User's email address.
  ///   - redirectTo: Redirect URL embedded in the email link.
  ///   - shouldCreateUser: Creates a new user, defaults to `true`.
  ///   - data: User's metadata.
  ///   - captchaToken: Captcha verification token.
  public func signInWithOTP(
    email: String,
    redirectTo: URL? = nil,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    await sessionManager.remove()

    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    try await api.execute(
      .init(
        path: "/otp",
        method: "POST",
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) }
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          OTPParams(
            email: email,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
  }

  /// Log in user using a one-time password (OTP)..
  ///
  /// - Parameters:
  ///   - phone: User's phone with international prefix.
  ///   - shouldCreateUser: Creates a new user, defaults to `true`.
  ///   - data: User's metadata.
  ///   - captchaToken: Captcha verification token.
  public func signInWithOTP(
    phone: String,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    await sessionManager.remove()
    try await api.execute(
      .init(
        path: "/otp",
        method: "POST",
        body: configuration.encoder.encode(
          OTPParams(
            phone: phone,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  public func exchangeCodeForSession(authCode: String) async throws -> Session {
    guard let codeVerifier = try codeVerifierStorage.getCodeVerifier() else {
      throw GoTrueError.pkce(.codeVerifierNotFound)
    }
    do {
      let session: Session = try await api.execute(
        .init(
          path: "/token",
          method: "POST",
          query: [URLQueryItem(name: "grant_type", value: "pkce")],
          body: configuration.encoder.encode(
            [
              "auth_code": authCode,
              "code_verifier": codeVerifier,
            ]
          )
        )
      )
      .decoded(decoder: configuration.decoder)

      try codeVerifierStorage.deleteCodeVerifier()

      try await sessionManager.update(session)
      await eventEmitter.emit(.signedIn)

      return session
    } catch {
      throw error
    }
  }

  /// Log in an existing user via a third-party provider.
  public func getOAuthSignInURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) throws -> URL {
    guard
      var components = URLComponents(
        url: configuration.url.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false
      )
    else {
      throw URLError(.badURL)
    }

    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "provider", value: provider.rawValue)
    ]

    if let scopes {
      queryItems.append(URLQueryItem(name: "scopes", value: scopes))
    }

    if let redirectTo {
      queryItems.append(URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString))
    }

    queryItems.append(contentsOf: queryParams.map(URLQueryItem.init))

    components.queryItems = queryItems

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return url
  }

  /// Gets the session data from a OAuth2 callback URL.
  @discardableResult
  public func session(from url: URL) async throws -> Session {
    if configuration.flowType == .implicit, !isImplicitGrantFlow(url: url) {
      throw GoTrueError.invalidImplicitGrantFlowURL
    }

    if configuration.flowType == .pkce, !isPKCEFlow(url: url) {
      throw GoTrueError.pkce(.invalidPKCEFlowURL)
    }

    let params = extractParams(from: url)

    if isPKCEFlow(url: url) {
      guard let code = params.first(where: { $0.name == "code" })?.value else {
        throw GoTrueError.pkce(.codeVerifierNotFound)
      }

      let session = try await exchangeCodeForSession(authCode: code)
      return session
    }

    if let errorDescription = params.first(where: { $0.name == "error_description" })?.value {
      throw GoTrueError.api(.init(errorDescription: errorDescription))
    }

    guard
      let accessToken = params.first(where: { $0.name == "access_token" })?.value,
      let expiresIn = params.first(where: { $0.name == "expires_in" })?.value,
      let refreshToken = params.first(where: { $0.name == "refresh_token" })?.value,
      let tokenType = params.first(where: { $0.name == "token_type" })?.value
    else {
      throw URLError(.badURL)
    }

    let providerToken = params.first(where: { $0.name == "provider_token" })?.value
    let providerRefreshToken = params.first(where: { $0.name == "provider_refresh_token" })?.value

    let user = try await api.execute(
      .init(
        path: "/user",
        method: "GET",
        headers: ["Authorization": "\(tokenType) \(accessToken)"]
      )
    ).decoded(as: User.self, decoder: configuration.decoder)

    let session = Session(
      providerToken: providerToken,
      providerRefreshToken: providerRefreshToken,
      accessToken: accessToken,
      tokenType: tokenType,
      expiresIn: Double(expiresIn) ?? 0,
      refreshToken: refreshToken,
      user: user
    )

    try await sessionManager.update(session)
    await eventEmitter.emit(.signedIn)

    if let type = params.first(where: { $0.name == "type" })?.value, type == "recovery" {
      await eventEmitter.emit(.passwordRecovery)
    }

    return session
  }

  /// Sets the session data from the current session. If the current session is expired, setSession
  /// will take care of refreshing it to obtain a new session.
  ///
  /// If the refresh token is invalid and the current session has expired, an error will be thrown.
  /// This method will use the exp claim defined in the access token.
  /// - Parameters:
  ///   - accessToken: The current access token.
  ///   - refreshToken: The current refresh token.
  /// - Returns: A new valid session.
  @discardableResult
  public func setSession(accessToken: String, refreshToken: String) async throws -> Session {
    let now = Date()
    var expiresAt = now
    var hasExpired = true
    var session: Session?

    let jwt = try decode(jwt: accessToken)
    if let exp = jwt["exp"] as? TimeInterval {
      expiresAt = Date(timeIntervalSince1970: exp)
      hasExpired = expiresAt <= now
    } else {
      throw GoTrueError.missingExpClaim
    }

    if hasExpired {
      session = try await refreshSession(refreshToken: refreshToken)
    } else {
      let user = try await api.authorizedExecute(.init(path: "/user", method: "GET"))
        .decoded(as: User.self, decoder: configuration.decoder)
      session = Session(
        accessToken: accessToken,
        tokenType: "bearer",
        expiresIn: expiresAt.timeIntervalSince(now),
        refreshToken: refreshToken,
        user: user
      )
    }

    guard let session else {
      throw GoTrueError.sessionNotFound
    }

    try await sessionManager.update(session)
    await eventEmitter.emit(.tokenRefreshed)
    return session
  }

  /// Signs out the current user, if there is a logged in user.
  public func signOut() async throws {
    do {
      _ = try await sessionManager.session()
      try await api.authorizedExecute(
        .init(
          path: "/logout",
          method: "POST"
        )
      )
      await sessionManager.remove()
      await eventEmitter.emit(.signedOut)
    } catch {
      await eventEmitter.emit(.signedOut)
      throw error
    }
  }

  /// Log in an user given a User supplied OTP received via email.
  @discardableResult
  public func verifyOTP(
    email: String,
    token: String,
    type: OTPType,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _verifyOTP(
      request: .init(
        path: "/verify",
        method: "POST",
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) }
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          VerifyOTPParams(
            email: email,
            token: token,
            type: type,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Log in an user given a User supplied OTP received via mobile.
  @discardableResult
  public func verifyOTP(
    phone: String,
    token: String,
    type: OTPType,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _verifyOTP(
      request: .init(
        path: "/verify",
        method: "POST",
        body: configuration.encoder.encode(
          VerifyOTPParams(
            phone: phone,
            token: token,
            type: type,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  private func _verifyOTP(request: Request) async throws -> AuthResponse {
    await sessionManager.remove()

    let response = try await api.execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.decoder
    )

    if let session = response.session {
      try await sessionManager.update(session)
      await eventEmitter.emit(.signedIn)
    }

    return response
  }

  /// Updates user data, if there is a logged in user.
  @discardableResult
  public func update(user: UserAttributes) async throws -> User {
    var user = user

    if user.email != nil {
      let (codeChallenge, codeChallengeMethod) = prepareForPKCE()
      user.codeChallenge = codeChallenge
      user.codeChallengeMethod = codeChallengeMethod
    }

    var session = try await sessionManager.session()
    let updatedUser = try await api.authorizedExecute(
      .init(path: "/user", method: "PUT", body: configuration.encoder.encode(user))
    ).decoded(as: User.self, decoder: configuration.decoder)
    session.user = updatedUser
    try await sessionManager.update(session)
    await eventEmitter.emit(.userUpdated)
    return updatedUser
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await api.execute(
      .init(
        path: "/recover",
        method: "POST",
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) }
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          RecoverParams(
            email: email,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  @discardableResult
  public func refreshSession(refreshToken: String) async throws -> Session {
    let session = try await api.execute(
      .init(
        path: "/token",
        method: "POST",
        query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
        body: configuration.encoder.encode(UserCredentials(refreshToken: refreshToken))
      )
    ).decoded(as: Session.self, decoder: configuration.decoder)

    if session.user.phoneConfirmedAt != nil || session.user.emailConfirmedAt != nil
      || session
        .user.confirmedAt != nil
    {
      try await sessionManager.update(session)
      await eventEmitter.emit(.signedIn)
    }

    return session
  }

  private func emitInitialSession(forStreamWithID id: UUID) async {
    _debug("start")
    defer { _debug("end") }

    let session = try? await self.session
    await eventEmitter.emit(session != nil ? .signedIn : .signedOut, id)
  }

  private func _debug(
    _ message: String,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    debugPrint("[GoTrueClient] \(function):\(line) \(message)")
  }

  private func isImplicitGrantFlow(url: URL) -> Bool {
    let fragments = extractParams(from: url)
    return fragments.contains {
      $0.name == "access_token" || $0.name == "error_description"
    }
  }

  private func isPKCEFlow(url: URL) -> Bool {
    let fragments = extractParams(from: url)
    let currentCodeVerifier = try? codeVerifierStorage.getCodeVerifier()
    return fragments.contains(where: { $0.name == "code" }) && currentCodeVerifier != nil
  }
}

extension GoTrueClient {
  public static let didChangeAuthStateNotification = Notification.Name(
    "DID_CHANGE_AUTH_STATE_NOTIFICATION")
}
