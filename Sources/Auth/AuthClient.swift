import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor AuthClient {
  /// FetchHandler is a type alias for asynchronous network request handling.
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)

  /// Configuration struct represents the client configuration.
  public struct Configuration: Sendable {
    public let url: URL
    public var headers: [String: String]
    public let flowType: AuthFlowType
    public let localStorage: AuthLocalStorage
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let fetch: FetchHandler

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - localStorage: The storage mechanism for local data.
    ///   - encoder: The JSON encoder to use for encoding requests.
    ///   - decoder: The JSON decoder to use for decoding responses.
    ///   - fetch: The asynchronous fetch handler for network requests.
    public init(
      url: URL,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      localStorage: AuthLocalStorage,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url
      self.headers = headers
      self.flowType = flowType
      self.localStorage = localStorage
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

  private var codeVerifierStorage: CodeVerifierStorage {
    Dependencies.current.value!.codeVerifierStorage
  }

  private var eventEmitter: EventEmitter {
    Dependencies.current.value!.eventEmitter
  }

  private var currentDate: @Sendable () -> Date {
    Dependencies.current.value!.currentDate
  }

  /// Returns the session, refreshing it if necessary.
  ///
  /// If no session can be found, a ``AuthError/sessionNotFound`` error is thrown.
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Namespace for accessing multi-factor authentication API.
  public let mfa: AuthMFA

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type..
  ///   - localStorage: The storage mechanism for local data..
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  public init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    localStorage: AuthLocalStorage,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
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

  /// Initializes a AuthClient with a specific configuration.
  ///
  /// - Parameters:
  ///   - configuration: The client configuration.
  public init(configuration: Configuration) {
    let api = APIClient.live(http: HTTPClient(fetchHandler: configuration.fetch))

    self.init(
      configuration: configuration,
      sessionManager: .live,
      codeVerifierStorage: .live,
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
    mfa = AuthMFA()

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
        ),
        codeVerifierStorage: codeVerifierStorage
      )
    )
  }

  /// Listen for auth state changes.
  ///
  /// An `.initialSession` is always emitted when this method is called.
  public var authStateChanges: AsyncStream<(
    event: AuthChangeEvent,
    session: Session?
  )> {
    let (id, stream) = eventEmitter.attachListener()

    Task { [id] in
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
        method: .post,
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          SignUpRequest(
            email: email,
            password: password,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
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
        method: .post,
        body: configuration.encoder.encode(
          SignUpRequest(
            password: password,
            phone: phone,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
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
      eventEmitter.emit(.signedIn, session: session)
    }

    return response
  }

  /// Log in an existing user with an email and password.
  @discardableResult
  public func signIn(email: String, password: String) async throws -> Session {
    try await _signIn(
      request: .init(
        path: "/token",
        method: .post,
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
        method: .post,
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
        method: .post,
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
      eventEmitter.emit(.signedIn, session: session)
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

    _ = try await api.execute(
      .init(
        path: "/otp",
        method: .post,
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          OTPParams(
            email: email,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
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
    _ = try await api.execute(
      .init(
        path: "/otp",
        method: .post,
        body: configuration.encoder.encode(
          OTPParams(
            phone: phone,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  public func exchangeCodeForSession(authCode: String) async throws -> Session {
    guard let codeVerifier = try codeVerifierStorage.getCodeVerifier() else {
      throw AuthError.pkce(.codeVerifierNotFound)
    }
    do {
      let session: Session = try await api.execute(
        .init(
          path: "/token",
          method: .post,
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
      eventEmitter.emit(.signedIn, session: session)

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
      URLQueryItem(name: "provider", value: provider.rawValue),
    ]

    if let scopes {
      queryItems.append(URLQueryItem(name: "scopes", value: scopes))
    }

    if let redirectTo {
      queryItems.append(URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString))
    }

    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    if let codeChallenge {
      queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
    }

    if let codeChallengeMethod {
      queryItems.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod))
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
      throw AuthError.invalidImplicitGrantFlowURL
    }

    if configuration.flowType == .pkce, !isPKCEFlow(url: url) {
      throw AuthError.pkce(.invalidPKCEFlowURL)
    }

    let params = extractParams(from: url)

    if isPKCEFlow(url: url) {
      guard let code = params.first(where: { $0.name == "code" })?.value else {
        throw AuthError.pkce(.codeVerifierNotFound)
      }

      let session = try await exchangeCodeForSession(authCode: code)
      return session
    }

    if let errorDescription = params.first(where: { $0.name == "error_description" })?.value {
      throw AuthError.api(.init(errorDescription: errorDescription))
    }

    guard
      let accessToken = params.first(where: { $0.name == "access_token" })?.value,
      let expiresIn = params.first(where: { $0.name == "expires_in" }).map(\.value)
      .flatMap(TimeInterval.init),
      let refreshToken = params.first(where: { $0.name == "refresh_token" })?.value,
      let tokenType = params.first(where: { $0.name == "token_type" })?.value
    else {
      throw URLError(.badURL)
    }

    let expiresAt = params.first(where: { $0.name == "expires_at" }).map(\.value)
      .flatMap(TimeInterval.init)
    let providerToken = params.first(where: { $0.name == "provider_token" })?.value
    let providerRefreshToken = params.first(where: { $0.name == "provider_refresh_token" })?.value

    let user = try await api.execute(
      .init(
        path: "/user",
        method: .get,
        headers: ["Authorization": "\(tokenType) \(accessToken)"]
      )
    ).decoded(as: User.self, decoder: configuration.decoder)

    let session = Session(
      providerToken: providerToken,
      providerRefreshToken: providerRefreshToken,
      accessToken: accessToken,
      tokenType: tokenType,
      expiresIn: expiresIn,
      expiresAt: expiresAt ?? currentDate().addingTimeInterval(expiresIn).timeIntervalSince1970,
      refreshToken: refreshToken,
      user: user
    )

    try await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)

    if let type = params.first(where: { $0.name == "type" })?.value, type == "recovery" {
      eventEmitter.emit(.passwordRecovery, session: session)
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
    let now = currentDate()
    var expiresAt = now
    var hasExpired = true
    var session: Session

    let jwt = try decode(jwt: accessToken)
    if let exp = jwt["exp"] as? TimeInterval {
      expiresAt = Date(timeIntervalSince1970: exp)
      hasExpired = expiresAt <= now
    } else {
      throw AuthError.missingExpClaim
    }

    if hasExpired {
      session = try await refreshSession(refreshToken: refreshToken)
    } else {
      let user = try await user(jwt: accessToken)
      session = Session(
        accessToken: accessToken,
        tokenType: "bearer",
        expiresIn: expiresAt.timeIntervalSince(now),
        expiresAt: expiresAt.timeIntervalSince1970,
        refreshToken: refreshToken,
        user: user
      )
    }

    try await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)
    return session
  }

  /// Signs out the current user, if there is a logged in user.
  ///
  /// If using ``SignOutScope/others`` scope, no ``AuthChangeEvent/signedOut`` event is fired.
  /// - Parameter scope: Specifies which sessions should be logged out.
  public func signOut(scope: SignOutScope = .global) async throws {
    do {
      // Make sure we have a valid session.
      _ = try await sessionManager.session()

      try await api.authorizedExecute(
        .init(
          path: "/logout",
          method: .post,
          query: [URLQueryItem(name: "scope", value: scope.rawValue)]
        )
      )
    } catch {
      // ignore 404s since user might not exist anymore
      // ignore 401s since an invalid or expired JWT should sign out the current session
      let ignoredCodes = Set([404, 401])

      if case let AuthError.api(apiError) = error, let code = apiError.code,
         !ignoredCodes.contains(code)
      {
        throw error
      }
    }

    if scope != .others {
      await sessionManager.remove()
      eventEmitter.emit(.signedOut, session: nil)
    }
  }

  /// Log in an user given a User supplied OTP received via email.
  @discardableResult
  public func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _verifyOTP(
      request: .init(
        path: "/verify",
        method: .post,
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          VerifyOTPParams.email(
            VerifyEmailOTPParams(
              email: email,
              token: token,
              type: type,
              gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
            )
          )
        )
      ),
      shouldRemoveSession: type != .emailChange
    )
  }

  /// Log in an user given a User supplied OTP received via mobile.
  @discardableResult
  public func verifyOTP(
    phone: String,
    token: String,
    type: MobileOTPType,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _verifyOTP(
      request: .init(
        path: "/verify",
        method: .post,
        body: configuration.encoder.encode(
          VerifyOTPParams.mobile(
            VerifyMobileOTPParams(
              phone: phone,
              token: token,
              type: type,
              gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
            )
          )
        )
      ),
      shouldRemoveSession: type != .phoneChange
    )
  }

  private func _verifyOTP(
    request: Request,
    shouldRemoveSession: Bool
  ) async throws -> AuthResponse {
    if shouldRemoveSession {
      await sessionManager.remove()
    }

    let response = try await api.execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.decoder
    )

    if let session = response.session {
      try await sessionManager.update(session)
      eventEmitter.emit(.signedIn, session: session)
    }

    return response
  }

  /// Resends an existing signup confirmation email or email change email.
  ///
  /// To obfuscate whether such the email already exists in the system this method succeeds in both
  /// cases.
  public func resend(
    email: String,
    type: ResendEmailType,
    emailRedirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    if type != .emailChange {
      await sessionManager.remove()
    }

    _ = try await api.execute(
      Request(
        path: "/resend",
        method: .post,
        query: [
          emailRedirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          ResendEmailParams(
            type: type,
            email: email,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Resends an existing SMS OTP or phone change OTP.
  /// - Returns: An object containing the unique ID of the message as reported by the SMS sending
  /// provider. Useful for tracking deliverability problems.
  ///
  /// To obfuscate whether such the phone number already exists in the system this method succeeds
  /// in both cases.
  @discardableResult
  public func resend(
    phone: String,
    type: ResendMobileType,
    captchaToken: String? = nil
  ) async throws -> ResendMobileResponse {
    if type != .phoneChange {
      await sessionManager.remove()
    }

    return try await api.execute(
      Request(
        path: "/resend",
        method: .post,
        body: configuration.encoder.encode(
          ResendMobileParams(
            type: type,
            phone: phone,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Gets the current user details if there is an existing session.
  /// - Parameter jwt: Takes in an optional access token jwt. If no jwt is provided, user() will
  /// attempt to get the jwt from the current session.
  ///
  /// Should be used only when you require the most current user data. For faster results,
  /// session.user is recommended.
  public func user(jwt: String? = nil) async throws -> User {
    var request = Request(path: "/user", method: .get)

    if let jwt {
      request.headers["Authorization"] = "Bearer \(jwt)"
      return try await api.execute(request).decoded(decoder: configuration.decoder)
    }

    return try await api.authorizedExecute(request).decoded(decoder: configuration.decoder)
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
      .init(path: "/user", method: .put, body: configuration.encoder.encode(user))
    ).decoded(as: User.self, decoder: configuration.decoder)
    session.user = updatedUser
    try await sessionManager.update(session)
    eventEmitter.emit(.userUpdated, session: session)
    return updatedUser
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await api.execute(
      .init(
        path: "/recover",
        method: .post,
        query: [
          redirectTo.map { URLQueryItem(name: "redirect_to", value: $0.absoluteString) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(
          RecoverParams(
            email: email,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
  }

  /// Refresh and return a new session, regardless of expiry status.
  /// - Parameter refreshToken: The optional refresh token to use for refreshing the session. If
  /// none is provided then this method tries to load the refresh token from the current session.
  /// - Returns: A new session.
  @discardableResult
  public func refreshSession(refreshToken: String? = nil) async throws -> Session {
    var credentials = UserCredentials(refreshToken: refreshToken)
    if credentials.refreshToken == nil {
      credentials.refreshToken = try await sessionManager.session(shouldValidateExpiration: false)
        .refreshToken
    }

    let session = try await api.execute(
      .init(
        path: "/token",
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
        body: configuration.encoder.encode(credentials)
      )
    ).decoded(as: Session.self, decoder: configuration.decoder)

    if session.user.phoneConfirmedAt != nil || session.user.emailConfirmedAt != nil
      || session
      .user.confirmedAt != nil
    {
      try await sessionManager.update(session)
      eventEmitter.emit(.tokenRefreshed, session: session)
    }

    return session
  }

  private func emitInitialSession(forStreamWithID id: UUID) async {
    let session = try? await session
    eventEmitter.emit(.initialSession, session, id)
  }

  private func prepareForPKCE() -> (codeChallenge: String?, codeChallengeMethod: String?) {
    if configuration.flowType == .pkce {
      let codeVerifier = PKCE.generateCodeVerifier()

      do {
        try codeVerifierStorage.storeCodeVerifier(codeVerifier)
      } catch {
        assertionFailure(
          """
          An error occurred while storing the code verifier,
          PKCE flow may not work as expected.

          Error: \(error.localizedDescription)
          """
        )
      }

      let codeChallenge = PKCE.generateCodeChallenge(from: codeVerifier)
      let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

      return (codeChallenge, codeChallengeMethod)
    }

    return (nil, nil)
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

extension AuthClient {
  /// Notification posted when an auth state event is triggered.
  public static let didChangeAuthStateNotification = Notification.Name(
    "AuthClient.didChangeAuthStateNotification"
  )

  /// A user info key to retrieve the ``AuthChangeEvent`` value for a
  /// ``AuthClient/didChangeAuthStateNotification`` notification.
  public static let authChangeEventInfoKey = "AuthClient.authChangeEvent"

  /// A user info key to retrieve the ``Session`` value for a
  /// ``AuthClient/didChangeAuthStateNotification`` notification.
  public static let authChangeSessionInfoKey = "AuthClient.authChangeSession"
}
