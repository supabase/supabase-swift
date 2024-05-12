import _Helpers
import ConcurrencyExtras
import Foundation

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public final class AuthClient: Sendable {
  private var api: APIClient { Current.api }
  private var configuration: AuthClient.Configuration { Current.configuration }
  private var codeVerifierStorage: CodeVerifierStorage { Current.codeVerifierStorage }
  private var date: @Sendable () -> Date { Current.date }
  private var sessionManager: SessionManager { Current.sessionManager }
  private var eventEmitter: AuthStateChangeEventEmitter { Current.eventEmitter }

  /// Returns the session, refreshing it if necessary.
  ///
  /// If no session can be found, a ``AuthError/sessionNotFound`` error is thrown.
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Namespace for accessing multi-factor authentication API.
  public let mfa = AuthMFA()
  /// Namespace for the GoTrue admin methods.
  /// - Warning: This methods requires `service_role` key, be careful to never expose `service_role`
  /// key in the client.
  public let admin = AuthAdmin()

  /// Initializes a AuthClient with a specific configuration.
  ///
  /// - Parameters:
  ///   - configuration: The client configuration.
  public init(configuration: Configuration) {
    Current = Dependencies(
      configuration: configuration,
      sessionRefresher: SessionRefresher { [weak self] in
        try await self?.refreshSession(refreshToken: $0) ?? .empty
      },
      http: HTTPClient(configuration: configuration)
    )
  }

  /// Listen for auth state changes.
  /// - Parameter listener: Block that executes when a new event is emitted.
  /// - Returns: A handle that can be used to manually unsubscribe.
  ///
  /// - Note: This method blocks execution until the ``AuthChangeEvent/initialSession`` event is
  /// emitted. Although this operation is usually fast, in case of the current stored session being
  /// invalid, a call to the endpoint is necessary for refreshing the session.
  @discardableResult
  public func onAuthStateChange(
    _ listener: @escaping AuthStateChangeListener
  ) async -> some AuthStateChangeListenerRegistration {
    let token = eventEmitter.attach(listener)
    await emitInitialSession(forToken: token)
    return token
  }

  /// Listen for auth state changes.
  ///
  /// An `.initialSession` is always emitted when this method is called.
  public var authStateChanges: AsyncStream<(
    event: AuthChangeEvent,
    session: Session?
  )> {
    let (stream, continuation) = AsyncStream<(
      event: AuthChangeEvent,
      session: Session?
    )>.makeStream()

    Task {
      let handle = await onAuthStateChange { event, session in
        continuation.yield((event, session))
      }

      continuation.onTermination = { _ in
        handle.remove()
      }
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
        url: configuration.url.appendingPathComponent("signup"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectToURL).map { URLQueryItem(
            name: "redirect_to",
            value: $0.absoluteString
          ) },
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
        url: configuration.url.appendingPathComponent("signup"),
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

  private func _signUp(request: HTTPRequest) async throws -> AuthResponse {
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
  public func signIn(
    email: String,
    password: String,
    captchaToken: String? = nil
  ) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.encoder.encode(
          UserCredentials(
            email: email,
            password: password,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Log in an existing user with a phone and password.
  @discardableResult
  public func signIn(
    phone: String,
    password: String,
    captchaToken: String? = nil
  ) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.encoder.encode(
          UserCredentials(
            password: password,
            phone: phone,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
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
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "id_token")],
        body: configuration.encoder.encode(credentials)
      )
    )
  }

  /// Creates a new anonymous user.
  /// - Parameters:
  ///   - data: A custom data object to store the user's metadata. This maps to the
  /// `auth.users.raw_user_meta_data` column. The `data` should be a JSON object that includes
  /// user-specific info, such as their first and last name.
  ///   - captchaToken: Verification token received when the user completes the captcha.
  @discardableResult
  public func signInAnonymously(
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws -> Session {
    try await _signIn(
      request: HTTPRequest(
        url: configuration.url.appendingPathComponent("signup"),
        method: .post,
        body: configuration.encoder.encode(
          SignUpRequest(
            data: data,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) }
          )
        )
      )
    )
  }

  private func _signIn(request: HTTPRequest) async throws -> Session {
    await sessionManager.remove()

    let session = try await api.execute(request).decoded(
      as: Session.self,
      decoder: configuration.decoder
    )

    try await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)

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
        url: configuration.url.appendingPathComponent("otp"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectToURL).map { URLQueryItem(
            name: "redirect_to",
            value: $0.absoluteString
          ) },
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
  ///   - channel: Messaging channel to use (e.g `whatsapp` or `sms`), defaults to `sms`.
  ///   - shouldCreateUser: Creates a new user, defaults to `true`.
  ///   - data: User's metadata.
  ///   - captchaToken: Captcha verification token.
  ///
  /// - Note: You need to configure a WhatsApp sender on Twillo if you are using phone sign in with
  /// the `whatsapp` channel.
  public func signInWithOTP(
    phone: String,
    channel: MessagingChannel = .sms,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    await sessionManager.remove()
    _ = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("otp"),
        method: .post,
        body: configuration.encoder.encode(
          OTPParams(
            phone: phone,
            createUser: shouldCreateUser,
            channel: channel,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  /// Attempts a single-sign on using an enterprise Identity Provider.
  /// - Parameters:
  ///   - domain: The email domain to use for signing in.
  ///   - redirectTo: The URL to redirect the user to after they sign in with the third-party
  /// provider.
  ///   - captchaToken: The captcha token to be used for captcha verification.
  /// - Returns: A URL that you can use to initiate the provider's authentication flow.
  public func signInWithSSO(
    domain: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> SSOResponse {
    await sessionManager.remove()

    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("sso"),
        method: .post,
        body: configuration.encoder.encode(
          SignInWithSSORequest(
            providerId: nil,
            domain: domain,
            redirectTo: redirectTo ?? configuration.redirectToURL,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Attempts a single-sign on using an enterprise Identity Provider.
  /// - Parameters:
  ///   - providerId: The ID of the SSO provider to use for signing in.
  ///   - redirectTo: The URL to redirect the user to after they sign in with the third-party
  /// provider.
  ///   - captchaToken: The captcha token to be used for captcha verification.
  /// - Returns: A URL that you can use to initiate the provider's authentication flow.
  public func signInWithSSO(
    providerId: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> SSOResponse {
    await sessionManager.remove()

    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("sso"),
        method: .post,
        body: configuration.encoder.encode(
          SignInWithSSORequest(
            providerId: providerId,
            domain: nil,
            redirectTo: redirectTo ?? configuration.redirectToURL,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
        )
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  public func exchangeCodeForSession(authCode: String) async throws -> Session {
    guard let codeVerifier = codeVerifierStorage.get() else {
      throw AuthError.pkce(.codeVerifierNotFound)
    }

    let session: Session = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("token"),
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

    codeVerifierStorage.set(nil)

    try await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)

    return session
  }

  /// Get a URL which you can use to start an OAuth flow for a third-party provider.
  ///
  /// Use this method if you want to have full control over the OAuth flow implementation, once you
  /// have result URL with a OAuth token, use method ``session(from:)`` to load the session
  /// into the client.
  ///
  /// If that isn't the case, you should consider using
  /// ``signInWithOAuth(provider:redirectTo:scopes:queryParams:launchFlow:)`` or
  /// ``signInWithOAuth(provider:redirectTo:scopes:queryParams:configure:)``.
  public func getOAuthSignInURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) throws -> URL {
    try getURLForProvider(
      url: configuration.url.appendingPathComponent("authorize"),
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams
    )
  }

  /// Sign-in an existing user via a third-party provider.
  ///
  /// - Parameters:
  ///   - provider: The third-party provider.
  ///   - redirectTo: A URL to send the user to after they are confirmed.
  ///   - scopes: A space-separated list of scopes granted to the OAuth application.
  ///   - queryParams: Additional query params.
  ///   - launchFlow: A launch closure that you can use to implement the authentication flow. Use
  /// the `url` to initiate the flow and return a `URL` that contains the OAuth result.
  ///
  /// - Note: This method support the PKCE flow.
  @discardableResult
  public func signInWithOAuth(
    provider: Provider,
    redirectTo: URL? = nil,
    scopes: String? = nil,
    queryParams: [(name: String, value: String?)] = [],
    launchFlow: @MainActor @Sendable (_ url: URL) async throws -> URL
  ) async throws -> Session {
    guard let redirectTo = (redirectTo ?? configuration.redirectToURL) else {
      throw AuthError.invalidRedirectScheme
    }

    let url = try getOAuthSignInURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams
    )

    let resultURL = try await launchFlow(url)

    return try await session(from: resultURL)
  }

  #if canImport(AuthenticationServices)
    /// Sign-in an existing user via a third-party provider using ``ASWebAuthenticationSession``.
    ///
    /// - Parameters:
    ///   - provider: The third-party provider.
    ///   - redirectTo: A URL to send the user to after they are confirmed.
    ///   - scopes: A space-separated list of scopes granted to the OAuth application.
    ///   - queryParams: Additional query params.
    ///   - configure: A configuration closure that you can use to customize the internal
    /// ``ASWebAuthenticationSession`` object.
    ///
    /// - Note: This method support the PKCE flow.
    /// - Warning: Do not call `start()` on the `ASWebAuthenticationSession` object inside the
    /// `configure` closure, as the method implementation calls it already.
    @available(watchOS 6.2, tvOS 16.0, *)
    @discardableResult
    public func signInWithOAuth(
      provider: Provider,
      redirectTo: URL? = nil,
      scopes: String? = nil,
      queryParams: [(name: String, value: String?)] = [],
      configure: @Sendable (_ session: ASWebAuthenticationSession) -> Void = { _ in }
    ) async throws -> Session {
      try await signInWithOAuth(
        provider: provider,
        redirectTo: redirectTo,
        scopes: scopes,
        queryParams: queryParams
      ) { @MainActor url in
        try await withCheckedThrowingContinuation { continuation in
          guard let callbackScheme = (configuration.redirectToURL ?? redirectTo)?.scheme else {
            continuation.resume(throwing: AuthError.invalidRedirectScheme)
            return
          }

          #if !os(tvOS) && !os(watchOS)
            var presentationContextProvider: DefaultPresentationContextProvider?
          #endif

          let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
          ) { url, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let url {
              continuation.resume(returning: url)
            } else {
              continuation.resume(throwing: AuthError.missingURL)
            }

            #if !os(tvOS) && !os(watchOS)
              // Keep a strong reference to presentationContextProvider until the flow completes.
              _ = presentationContextProvider
            #endif
          }

          configure(session)

          #if !os(tvOS) && !os(watchOS)
            if session.presentationContextProvider == nil {
              presentationContextProvider = DefaultPresentationContextProvider()
              session.presentationContextProvider = presentationContextProvider
            }
          #endif

          session.start()
        }
      }
    }
  #endif

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
      guard let code = params["code"] else {
        throw AuthError.pkce(.codeVerifierNotFound)
      }

      let session = try await exchangeCodeForSession(authCode: code)
      return session
    }

    if let errorDescription = params["error_description"] {
      throw AuthError.api(.init(errorDescription: errorDescription))
    }

    guard
      let accessToken = params["access_token"],
      let expiresIn = params["expires_in"].flatMap(TimeInterval.init),
      let refreshToken = params["refresh_token"],
      let tokenType = params["token_type"]
    else {
      throw URLError(.badURL)
    }

    let expiresAt = params["expires_at"].flatMap(TimeInterval.init)
    let providerToken = params["provider_token"]
    let providerRefreshToken = params["provider_refresh_token"]

    let user = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("user"),
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
      expiresAt: expiresAt ?? date().addingTimeInterval(expiresIn).timeIntervalSince1970,
      refreshToken: refreshToken,
      user: user
    )

    try await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)

    if let type = params["type"], type == "recovery" {
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
    let now = date()
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
    guard let accessToken = currentSession?.accessToken else {
        configuration.logger?.warning("signOut called without a session")
        return
    }

    if scope != .others {
        await sessionManager.remove()
        eventEmitter.emit(.signedOut, session: nil)
    }

    do {
      _ = try await api.execute(
        .init(
          url: configuration.url.appendingPathComponent("logout"),
          method: .post,
          query: [URLQueryItem(name: "scope", value: scope.rawValue)], 
          headers: [.init(name: "Authorization", value: "Bearer \(accessToken)")]
        )
      )
    } catch {
      // ignore 404s since user might not exist anymore
      // ignore 401s, and 403s since an invalid or expired JWT should sign out the current session.
      let ignoredCodes = Set([404, 403, 401])

      if case let AuthError.api(apiError) = error, let code = apiError.code,
         !ignoredCodes.contains(code)
      {
        throw error
      }
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
        url: configuration.url.appendingPathComponent("verify"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectToURL).map { URLQueryItem(
            name: "redirect_to",
            value: $0.absoluteString
          ) },
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
        url: configuration.url.appendingPathComponent("verify"),
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
    request: HTTPRequest,
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
      HTTPRequest(
        url: configuration.url.appendingPathComponent("resend"),
        method: .post,
        query: [
          (emailRedirectTo ?? configuration.redirectToURL).map { URLQueryItem(
            name: "redirect_to",
            value: $0.absoluteString
          ) },
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
      HTTPRequest(
        url: configuration.url.appendingPathComponent("resend"),
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

  /// Sends a re-authentication OTP to the user's email or phone number.
  public func reauthenticate() async throws {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("reauthenticate"),
        method: .get
      )
    )
  }

  /// Returns the current session, if any.
  ///
  /// The session returned by this property may be expired. Use ``session`` for a session that is guaranteed to be valid.
  public var currentSession: Session? {
    try? configuration.localStorage.getSession()?.session
  }

  /// Returns the current user, if any.
  ///
  /// The user returned by this property may be outdated. Use ``user(jwt:)`` method to get an up-to-date user instance.
  public var currentUser: User? {
    try? configuration.localStorage.getSession()?.session.user
  }

  /// Gets the current user details if there is an existing session.
  /// - Parameter jwt: Takes in an optional access token jwt. If no jwt is provided, user() will
  /// attempt to get the jwt from the current session.
  ///
  /// Should be used only when you require the most current user data. For faster results, ``currentUser`` is recommended.
  public func user(jwt: String? = nil) async throws -> User {
    var request = HTTPRequest(url: configuration.url.appendingPathComponent("user"), method: .get)

    if let jwt {
      request.headers["Authorization"] = "Bearer \(jwt)"
      return try await api.execute(request).decoded(decoder: configuration.decoder)
    }

    return try await api.authorizedExecute(request).decoded(decoder: configuration.decoder)
  }

  /// Updates user data, if there is a logged in user.
  @discardableResult
  public func update(user: UserAttributes, redirectTo: URL? = nil) async throws -> User {
    var user = user

    if user.email != nil {
      let (codeChallenge, codeChallengeMethod) = prepareForPKCE()
      user.codeChallenge = codeChallenge
      user.codeChallengeMethod = codeChallengeMethod
    }

    var session = try await sessionManager.session()
    let updatedUser = try await api.authorizedExecute(
      .init(
        url: configuration.url.appendingPathComponent("user"),
        method: .put,
        query: [
            (redirectTo ?? configuration.redirectToURL).map { URLQueryItem(
                name: "redirect_to",
                value: $0.absoluteString
            ) },
        ].compactMap { $0 },
        body: configuration.encoder.encode(user)
      )
    ).decoded(as: User.self, decoder: configuration.decoder)
    session.user = updatedUser
    try await sessionManager.update(session)
    eventEmitter.emit(.userUpdated, session: session)
    return updatedUser
  }

  /// Gets all the identities linked to a user.
  public func userIdentities() async throws -> [UserIdentity] {
    try await user().identities ?? []
  }

  /// Returns the URL to link the user's identity with an OAuth provider.
  ///
  /// This method supports the PKCE flow.
  ///
  /// - Parameters:
  ///   - provider: The provider you want to link the user with.
  ///   - scopes: The scopes to request from the OAuth provider.
  ///   - redirectTo: The redirect URL to use, specify a configured deep link.
  ///   - queryParams: Additional query parameters to use.
  public func getLinkIdentityURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) async throws -> OAuthResponse {
    let url = try getURLForProvider(
      url: configuration.url.appendingPathComponent("user/identities/authorize"),
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams,
      skipBrowserRedirect: true
    )

    struct Response: Codable {
      let url: URL
    }

    let response = try await api.authorizedExecute(
      HTTPRequest(
        url: url,
        method: .get
      )
    )
    .decoded(as: Response.self, decoder: configuration.decoder)

    return OAuthResponse(provider: provider, url: response.url)
  }

  /// Unlinks an identity from a user by deleting it. The user will no longer be able to sign in
  /// with that identity once it's unlinked.
  public func unlinkIdentity(_ identity: UserIdentity) async throws {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("user/identities/\(identity.identityId)"),
        method: .delete
      )
    )
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
        url: configuration.url.appendingPathComponent("recover"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectToURL).map { URLQueryItem(
            name: "redirect_to",
            value: $0.absoluteString
          ) },
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
        url: configuration.url.appendingPathComponent("token"),
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

  private func emitInitialSession(forToken token: ObservationToken) async {
    let session = try? await session
    eventEmitter.emit(.initialSession, session: session, token: token)
  }

  private func prepareForPKCE() -> (codeChallenge: String?, codeChallengeMethod: String?) {
    guard configuration.flowType == .pkce else {
      return (nil, nil)
    }

    let codeVerifier = PKCE.generateCodeVerifier()
    codeVerifierStorage.set(codeVerifier)

    let codeChallenge = PKCE.generateCodeChallenge(from: codeVerifier)
    let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

    return (codeChallenge, codeChallengeMethod)
  }

  private func isImplicitGrantFlow(url: URL) -> Bool {
    let fragments = extractParams(from: url)
    return fragments["access_token"] != nil || fragments["error_description"] != nil
  }

  private func isPKCEFlow(url: URL) -> Bool {
    let fragments = extractParams(from: url)
    let currentCodeVerifier = codeVerifierStorage.get()
    return fragments["code"] != nil && currentCodeVerifier != nil
  }

  private func getURLForProvider(
    url: URL,
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = [],
    skipBrowserRedirect: Bool? = nil
  ) throws -> URL {
    guard
      var components = URLComponents(
        url: url, resolvingAgainstBaseURL: false
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

    if let redirectTo = redirectTo ?? configuration.redirectToURL {
      queryItems.append(URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString))
    }

    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    if let codeChallenge {
      queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
    }

    if let codeChallengeMethod {
      queryItems.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod))
    }

    if let skipBrowserRedirect {
      queryItems.append(URLQueryItem(name: "skip_http_redirect", value: "\(skipBrowserRedirect)"))
    }

    queryItems.append(contentsOf: queryParams.map(URLQueryItem.init))

    components.queryItems = queryItems

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    return url
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

#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
  @MainActor
  final class DefaultPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
  {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
      ASPresentationAnchor()
    }
  }
#endif
