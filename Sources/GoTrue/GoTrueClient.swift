import Combine
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public final class GoTrueClient {
  public typealias FetchHandler = @Sendable (_ request: URLRequest) async throws -> (
    Data,
    URLResponse
  )

  public struct Configuration {
    public let url: URL
    public var headers: [String: String]
    public let localStorage: GoTrueLocalStorage
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let fetch: FetchHandler

    public init(
      url: URL,
      headers: [String: String] = [:],
      localStorage: GoTrueLocalStorage? = nil,
      encoder: JSONEncoder = .goTrue,
      decoder: JSONDecoder = .goTrue,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
    ) {
      self.url = url
      self.headers = headers
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

  private let configuration: Configuration
  private lazy var sessionManager = SessionManager(
    localStorage: self.configuration.localStorage,
    sessionRefresher: { try await self.refreshSession(refreshToken: $0) }
  )

  private let authEventChangeSubject = PassthroughSubject<AuthChangeEvent, Never>()
  /// Asynchronous sequence of authentication change events emitted during life of `GoTrueClient`.
  public var authEventChange: AnyPublisher<AuthChangeEvent, Never> {
    authEventChangeSubject.shareReplay(1).eraseToAnyPublisher()
  }

  //  private let initializationTask: Task<Void, Never>

  /// Returns the session, refreshing it if necessary.
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    localStorage: GoTrueLocalStorage? = nil,
    encoder: JSONEncoder = .goTrue,
    decoder: JSONDecoder = .goTrue,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        localStorage: localStorage,
        encoder: encoder,
        decoder: decoder,
        fetch: fetch
      ))
  }

  public init(configuration: Configuration) {
    var configuration = configuration
    configuration.headers["X-Client-Info"] = "gotrue-swift/\(version)"
    self.configuration = configuration

    Task {
      do {
        _ = try await sessionManager.session()
        authEventChangeSubject.send(.signedIn)
      } catch {
        authEventChangeSubject.send(.signedOut)
      }
    }
  }

  /// Initialize the client session from storage.
  ///
  /// This method should be called on the app startup, for making sure that the client is fully
  /// initialized
  /// before proceeding.
  //  public func initialize() async {
  //    await initializationTask.value
  //  }

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
    try await _signUp(
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
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
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
    let response = try await execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.decoder
    )

    if let session = response.session {
      try await sessionManager.update(session)
      authEventChangeSubject.send(.signedIn)
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

    let session = try await execute(request).decoded(
      as: Session.self,
      decoder: configuration.decoder
    )

    if session.user.emailConfirmedAt != nil || session.user.confirmedAt != nil {
      try await sessionManager.update(session)
      authEventChangeSubject.send(.signedIn)
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
    redirectTo _: URL? = nil,
    shouldCreateUser: Bool? = nil,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    await sessionManager.remove()
    try await execute(
      .init(
        path: "/otp",
        method: "POST",
        body: configuration.encoder.encode(
          OTPParams(
            email: email,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(GoTrueMetaSecurity.init(captchaToken:))
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
    shouldCreateUser: Bool? = nil,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    await sessionManager.remove()
    try await execute(
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

  @discardableResult
  public func refreshSession(refreshToken: String) async throws -> Session {
    do {
      let session = try await execute(
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
        authEventChangeSubject.send(.signedIn)
      }

      return session
    } catch {
      throw error
    }
  }

  /// Gets the session data from a OAuth2 callback URL.
  @discardableResult
  public func session(from url: URL, storeSession: Bool = true) async throws -> Session {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }

    let params = extractParams(from: components.fragment ?? "")

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

    let user = try await execute(
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

    if storeSession {
      try await sessionManager.update(session)
      authEventChangeSubject.send(.signedIn)

      if let type = params.first(where: { $0.name == "type" })?.value, type == "recovery" {
        authEventChangeSubject.send(.passwordRecovery)
      }
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
      let user = try await authorizedExecute(.init(path: "/user", method: "GET"))
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
    authEventChangeSubject.send(.tokenRefreshed)
    return session
  }

  /// Signs out the current user, if there is a logged in user.
  public func signOut() async throws {
    defer { authEventChangeSubject.send(.signedOut) }

    let session = try? await sessionManager.session()
    if session != nil {
      try await authorizedExecute(
        .init(
          path: "/logout",
          method: "POST"
        )
      )
      await sessionManager.remove()
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

    let response = try await execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.decoder
    )

    if let session = response.session {
      try await sessionManager.update(session)
      authEventChangeSubject.send(.signedIn)
    }

    return response
  }

  /// Updates user data, if there is a logged in user.
  @discardableResult
  public func update(user: UserAttributes) async throws -> User {
    var session = try await sessionManager.session()
    let user = try await authorizedExecute(
      .init(path: "/user", method: "PUT", body: configuration.encoder.encode(user))
    ).decoded(as: User.self, decoder: configuration.decoder)
    session.user = user
    try await sessionManager.update(session)
    authEventChangeSubject.send(.userUpdated)
    return user
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await execute(
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
  private func authorizedExecute(_ request: Request) async throws -> Response {
    let session = try await sessionManager.session()

    var request = request
    request.headers["Authorization"] = "Bearer \(session.accessToken)"

    return try await execute(request)
  }

  @discardableResult
  private func execute(_ request: Request) async throws -> Response {
    var request = request
    request.headers.merge(configuration.headers) { r, _ in r }
    let urlRequest = try request.urlRequest(withBaseURL: configuration.url)

    let (data, response) = try await configuration.fetch(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let apiError = try configuration.decoder.decode(GoTrueError.APIError.self, from: data)
      throw GoTrueError.api(apiError)
    }

    return Response(data: data, response: httpResponse)
  }
}
