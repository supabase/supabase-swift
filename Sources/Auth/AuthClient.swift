import Alamofire
import ConcurrencyExtras
import Foundation
import Logging

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(WatchKit)
  import WatchKit
#endif

#if canImport(ObjectiveC) && canImport(Combine)
  import Combine
#endif

typealias AuthClientID = Int

// Note: AuthClientLoggerDecorator removed for now - will be reimplemented in a future update

/// A client for Supabase Authentication.
///
/// The `AuthClient` provides a comprehensive authentication system with support for email/password,
/// OAuth providers, multi-factor authentication, and session management. It handles user registration,
/// login, logout, password recovery, and real-time authentication state changes.
///
/// ## Basic Usage
///
/// ```swift
/// // Initialize the client
/// let authClient = AuthClient(
///   url: URL(string: "https://your-project.supabase.co/auth/v1")!,
///   configuration: AuthClient.Configuration(
///     localStorage: KeychainLocalStorage()
///   )
/// )
///
/// // Check current user
/// if let user = await authClient.currentUser {
///   print("Logged in as: \(user.email ?? "Unknown")")
/// }
///
/// // Listen for auth state changes
/// for await (event, session) in await authClient.authStateChanges {
///   switch event {
///   case .signedIn:
///     print("User signed in")
///   case .signedOut:
///     print("User signed out")
///   case .tokenRefreshed:
///     print("Token refreshed")
///   }
/// }
/// ```
///
/// ## Authentication Methods
///
/// ### Email/Password Authentication
///
/// ```swift
/// // Sign up a new user
/// let authResponse = try await authClient.signUp(
///   email: "user@example.com",
///   password: "securepassword"
/// )
///
/// // Sign in existing user
/// let session = try await authClient.signIn(
///   email: "user@example.com",
///   password: "securepassword"
/// )
///
/// // Sign out
/// try await authClient.signOut()
/// ```
///
/// ### OAuth Authentication
///
/// ```swift
/// // Sign in with OAuth provider
/// let session = try await authClient.signInWithOAuth(
///   provider: .google,
///   redirectTo: URL(string: "myapp://auth/callback")
/// )
///
/// // Handle OAuth callback
/// try await authClient.session(from: callbackURL)
/// ```
///
/// ### Multi-Factor Authentication
///
/// ```swift
/// // Enroll MFA factor
/// let enrollment = try await authClient.mfa.enroll(
///   params: MFAEnrollParams(
///     factorType: .totp,
///     friendlyName: "My Authenticator App"
///   )
/// )
///
/// // Verify MFA challenge
/// let verification = try await authClient.mfa.verify(
///   params: MFAVerifyParams(
///     factorId: enrollment.id,
///     code: "123456"
///   )
/// )
/// ```
///
/// ## Session Management
///
/// ```swift
/// // Get current session (automatically refreshes if needed)
/// let session = try await authClient.session
///
/// // Get current user
/// let user = try await authClient.user()
///
/// // Update user profile
/// let updatedUser = try await authClient.updateUser(
///   attributes: UserAttributes(
///     data: ["display_name": "John Doe"]
///   )
/// )
/// ```
///
/// ## Password Recovery
///
/// ```swift
/// // Send password recovery email
/// try await authClient.resetPasswordForEmail(
///   "user@example.com",
///   redirectTo: URL(string: "myapp://reset-password")
/// )
///
/// // Update password
/// try await authClient.updateUser(
///   attributes: UserAttributes(password: "newpassword")
/// )
/// ```
public actor AuthClient {
  private static let globalClientID = LockIsolated(0)

  let clientID: AuthClientID
  let url: URL
  let configuration: AuthClient.Configuration

  let eventEmitter = AuthStateChangeEventEmitter()
  let alamofireSession: Alamofire.Session

  #if DEBUG  // Make sure there properties are mutable for testing.
    var pkce: PKCE = .live
    var date: @Sendable () -> Date = Date.init
    var urlOpener: URLOpener = .live
  #else
    let pkce: PKCE = .live
    let date: @Sendable () -> Date = Date.init
    let urlOpener: URLOpener = .live
  #endif

  private var _sessionStorage: SessionStorage?
  var sessionStorage: SessionStorage {
    if _sessionStorage == nil {
      _sessionStorage = SessionStorage.live(client: self)
    }
    return _sessionStorage!
  }

  private var _sessionManager: SessionManager?
  var sessionManager: SessionManager {
    if _sessionManager == nil {
      _sessionManager = SessionManager.live(client: self)
    }
    return _sessionManager!
  }

  /// Returns the current session, automatically refreshing it if necessary.
  ///
  /// This property provides a session that is guaranteed to be valid. If the current session
  /// is expired, it will automatically attempt to refresh using the refresh token. If no
  /// session exists or refresh fails, a ``AuthError/sessionMissing`` error is thrown.
  ///
  /// ## Example
  ///
  /// ```swift
  /// do {
  ///   let session = try await authClient.session
  ///   print("Access token: \(session.accessToken)")
  ///   print("User: \(session.user.email ?? "No email")")
  /// } catch AuthError.sessionMissing {
  ///   print("No active session - user needs to sign in")
  /// }
  /// ```
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Returns the current session, if any.
  ///
  /// The session returned by this property may be expired. Use ``session`` for a session that is guaranteed to be valid.
  /// This property is useful for checking if a user is logged in without triggering a refresh.
  ///
  /// ## Example
  ///
  /// ```swift
  /// if let session = await authClient.currentSession {
  ///   print("User is logged in: \(session.user.email ?? "Unknown")")
  ///   // Note: This session might be expired
  /// } else {
  ///   print("No user session found")
  /// }
  /// ```
  public var currentSession: Session? {
    sessionStorage.get()
  }

  /// Returns the current user, if any.
  ///
  /// The user returned by this property may be outdated. Use ``user(jwt:)`` method to get an up-to-date user instance.
  /// This property is useful for quick access to user information without making network requests.
  ///
  /// ## Example
  ///
  /// ```swift
  /// if let user = await authClient.currentUser {
  ///   print("Current user: \(user.email ?? "No email")")
  ///   print("User ID: \(user.id)")
  ///   print("Created at: \(user.createdAt)")
  /// } else {
  ///   print("No user logged in")
  /// }
  /// ```
  public var currentUser: User? {
    currentSession?.user
  }

  /// Namespace for accessing multi-factor authentication API.
  ///
  /// Use this property to access MFA-related functionality including enrolling factors,
  /// challenging users, and verifying MFA codes.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Enroll a TOTP factor
  /// let enrollment = try await authClient.mfa.enroll(
  ///   params: MFAEnrollParams(
  ///     factorType: .totp,
  ///     friendlyName: "My Authenticator App"
  ///   )
  /// )
  ///
  /// // Challenge the user
  /// let challenge = try await authClient.mfa.challenge(
  ///   params: MFAChallengeParams(factorId: enrollment.id)
  /// )
  ///
  /// // Verify the code
  /// let verification = try await authClient.mfa.verify(
  ///   params: MFAVerifyParams(
  ///     factorId: enrollment.id,
  ///     code: "123456"
  ///   )
  /// )
  /// ```
  public var mfa: AuthMFA {
    AuthMFA(client: self)
  }

  /// Namespace for the GoTrue admin methods.
  ///
  /// Use this property to access administrative functionality for user management.
  /// These methods require elevated permissions and should only be used on the server side.
  ///
  /// - Warning: This methods requires `service_role` key, be careful to never expose `service_role`
  /// key in the client.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Get user by ID
  /// let user = try await authClient.admin.getUserById(userId)
  ///
  /// // Create a new user
  /// let newUser = try await authClient.admin.createUser(
  ///   attributes: AdminUserAttributes(
  ///     email: "admin@example.com",
  ///     password: "securepassword",
  ///     emailConfirm: true
  ///   )
  /// )
  ///
  /// // Update user attributes
  /// let updatedUser = try await authClient.admin.updateUser(
  ///   uid: userId,
  ///   attributes: AdminUserAttributes(
  ///     data: ["role": "admin"]
  ///   )
  /// )
  /// ```
  public var admin: AuthAdmin {
    AuthAdmin(client: self)
  }

  /// Initializes a AuthClient with a specific configuration.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - configuration: The client configuration.
  public init(url: URL, configuration: Configuration) {
    self.url = url

    clientID = AuthClient.globalClientID.withValue {
      $0 += 1
      return $0
    }

    var configuration = configuration
    var headers = HTTPHeaders(configuration.headers)
    if headers["X-Client-Info"] == nil {
      headers["X-Client-Info"] = "auth-swift/\(version)"
    }

    headers[apiVersionHeaderNameHeaderKey] = apiVersions[._20240101]!.name.rawValue

    configuration.headers = headers.dictionary

    alamofireSession = configuration.session.newSession(adapters: [
      DefaultHeadersRequestAdapter(headers: headers)
    ])

    self.configuration = configuration

    Task { @MainActor in observeAppLifecycleChanges() }
  }

  #if canImport(ObjectiveC) && canImport(Combine)
    @MainActor
    private func observeAppLifecycleChanges() {
      var didBecomeActiveNotification: NSNotification.Name?
      var willResignActiveNotification: NSNotification.Name?

      #if canImport(UIKit)
        #if canImport(WatchKit)
          if #available(watchOS 7.0, *) {
            didBecomeActiveNotification = WKExtension.applicationDidBecomeActiveNotification
            willResignActiveNotification = WKExtension.applicationWillResignActiveNotification
          }
        #else
          didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
          willResignActiveNotification = UIApplication.willResignActiveNotification
        #endif
      #elseif canImport(AppKit)
        didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
        willResignActiveNotification = NSApplication.willResignActiveNotification
      #endif

      if let didBecomeActiveNotification, let willResignActiveNotification {
        var cancellables = Set<AnyCancellable>()

        NotificationCenter.default
          .publisher(for: didBecomeActiveNotification)
          .sink(
            receiveCompletion: { _ in
              // hold ref to cancellable until it completes
              _ = cancellables
            },
            receiveValue: { [weak self] _ in
              Task {
                await self?.handleDidBecomeActive()
              }
            }
          )
          .store(in: &cancellables)

        NotificationCenter.default
          .publisher(for: willResignActiveNotification)
          .sink(
            receiveCompletion: { _ in
              // hold ref to cancellable until it completes
              _ = cancellables
            },
            receiveValue: { [weak self] _ in
              Task {
                await self?.handleWillResignActive()
              }
            }
          )
          .store(in: &cancellables)
      }

    }

    private func handleDidBecomeActive() {
      if configuration.autoRefreshToken {
        startAutoRefresh()
      }
    }

    private func handleWillResignActive() {
      if configuration.autoRefreshToken {
        stopAutoRefresh()
      }
    }
  #else
    @MainActor
    private func observeAppLifecycleChanges() {
      // no-op
    }
  #endif

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
  public var authStateChanges:
    AsyncStream<
      (
        event: AuthChangeEvent,
        session: Session?
      )
    >
  {
    let (stream, continuation) = AsyncStream<
      (
        event: AuthChangeEvent,
        session: Session?
      )
    >.makeStream()

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
  ///   - data: Custom data object to store additional user metadata.
  ///   - redirectTo: The redirect URL embedded in the email link, defaults to ``Configuration/redirectToURL`` if not provided.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  public func signUp(
    email: String,
    password: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws(AuthError) -> AuthResponse {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await _signUp(
      body: SignUpRequest(
        email: email,
        password: password,
        data: data,
        gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
        codeChallenge: codeChallenge,
        codeChallengeMethod: codeChallengeMethod
      ),
      query: (redirectTo ?? configuration.redirectToURL).map {
        ["redirect_to": $0.absoluteString]
      }
    )
  }

  /// Creates a new user.
  /// - Parameters:
  ///   - phone: User's phone number with international prefix.
  ///   - password: Password for the user.
  ///   - channel: Messaging channel to use (e.g. whatsapp or sms).
  ///   - data: Custom data object to store additional user metadata.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  public func signUp(
    phone: String,
    password: String,
    channel: MessagingChannel = .sms,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws(AuthError) -> AuthResponse {
    try await _signUp(
      body: SignUpRequest(
        password: password,
        phone: phone,
        channel: channel,
        data: data,
        gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
      )
    )
  }

  private func _signUp(body: SignUpRequest, query: Parameters? = nil) async throws(AuthError)
    -> AuthResponse
  {
    let response = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("signup"),
        method: .post,
        query: query,
        body: body
      )
      .serializingDecodable(AuthResponse.self, decoder: JSONDecoder.auth)
      .value
    }

    if let session = response.session {
      await sessionManager.update(session)
      eventEmitter.emit(.signedIn, session: session)
    }

    return response
  }

  /// Log in an existing user with an email and password.
  /// - Parameters:
  ///   - email: User's email address.
  ///   - password: User's password.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  public func signIn(
    email: String,
    password: String,
    captchaToken: String? = nil
  ) async throws(AuthError) -> Session {
    try await _signIn(
      grantType: "password",
      credentials: UserCredentials(
        email: email,
        password: password,
        gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
      )
    )
  }

  /// Log in an existing user with a phone and password.
  /// - Parameters:
  ///   - email: User's phone number.
  ///   - password: User's password.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  public func signIn(
    phone: String,
    password: String,
    captchaToken: String? = nil
  ) async throws(AuthError) -> Session {
    try await _signIn(
      grantType: "password",
      credentials: UserCredentials(
        password: password,
        phone: phone,
        gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
      )
    )
  }

  /// Allows signing in with an ID token issued by certain supported providers.
  /// The ID token is verified for validity and a new session is established.
  @discardableResult
  public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws(AuthError)
    -> Session
  {
    try await _signIn(
      grantType: "id_token",
      credentials: credentials
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
  ) async throws(AuthError) -> Session {
    try await _signUp(
      body: SignUpRequest(
        data: data,
        gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) }
      )
    ).session!  // anonymous sign in will always return a session
  }

  private func _signIn<Credentials: Encodable & Sendable>(
    grantType: String,
    credentials: Credentials
  ) async throws(AuthError) -> Session {
    let session = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("token"),
        method: .post,
        query: ["grant_type": grantType],
        body: credentials
      )
      .serializingDecodable(Session.self, decoder: JSONDecoder.auth)
      .value
    }

    await sessionManager.update(session)
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
  ) async throws(AuthError) {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("otp"),
        method: .post,
        query: (redirectTo ?? self.configuration.redirectToURL).map {
          ["redirect_to": $0.absoluteString]
        },
        body:
          OTPParams(
            email: email,
            createUser: shouldCreateUser,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
          )
      )
      .serializingData()
      .value
    }
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
  /// - Note: You need to configure a WhatsApp sender on Twillo if you are using phone sign in with the `whatsapp` channel.
  public func signInWithOTP(
    phone: String,
    channel: MessagingChannel = .sms,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws(AuthError) {
    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("otp"),
        method: .post,
        body: OTPParams(
          phone: phone,
          createUser: shouldCreateUser,
          channel: channel,
          data: data,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      )
      .serializingData()
      .value
    }
  }

  /// Attempts a single-sign on using an enterprise Identity Provider.
  /// - Parameters:
  ///   - domain: The email domain to use for signing in.
  ///   - redirectTo: The URL to redirect the user to after they sign in with the third-party provider.
  ///   - captchaToken: The captcha token to be used for captcha verification.
  /// - Returns: A URL that you can use to initiate the provider's authentication flow.
  public func signInWithSSO(
    domain: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws(AuthError) -> SSOResponse {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("sso"),
        method: .post,
        body: SignInWithSSORequest(
          providerId: nil,
          domain: domain,
          redirectTo: redirectTo ?? self.configuration.redirectToURL,
          gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
          codeChallenge: codeChallenge,
          codeChallengeMethod: codeChallengeMethod
        )
      )
      .serializingDecodable(SSOResponse.self, decoder: JSONDecoder.auth)
      .value
    }
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
  ) async throws(AuthError) -> SSOResponse {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("sso"),
        method: .post,
        body: SignInWithSSORequest(
          providerId: providerId,
          domain: nil,
          redirectTo: redirectTo ?? self.configuration.redirectToURL,
          gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
          codeChallenge: codeChallenge,
          codeChallengeMethod: codeChallengeMethod
        )
      )
      .serializingDecodable(SSOResponse.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  public func exchangeCodeForSession(authCode: String) async throws(AuthError) -> Session {
    let codeVerifier = getCodeVerifier()

    if codeVerifier == nil {
      configuration.logger?.error(
        "code verifier not found, a code verifier should exist when calling this method."
      )
    }

    let session = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("token"),
        method: .post,
        query: ["grant_type": "pkce"],
        body: ["auth_code": authCode, "code_verifier": codeVerifier]
      )
      .serializingDecodable(Session.self, decoder: JSONDecoder.auth)
      .value
    }

    setCodeVerifier(nil)

    await sessionManager.update(session)
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
  ) throws(AuthError) -> URL {
    try wrappingError(or: mapToAuthError) {
      try self.getURLForProvider(
        url: self.url.appendingPathComponent("authorize"),
        provider: provider,
        scopes: scopes,
        redirectTo: redirectTo,
        queryParams: queryParams
      )
    }
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
  ) async throws(AuthError) -> Session {
    let url = try getOAuthSignInURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo ?? configuration.redirectToURL,
      queryParams: queryParams
    )

    do {
      let resultURL = try await launchFlow(url)
      return try await session(from: resultURL)
    } catch {
      throw mapToAuthError(error)
    }
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
    ) async throws(AuthError) -> Session {
      try await signInWithOAuth(
        provider: provider,
        redirectTo: redirectTo,
        scopes: scopes,
        queryParams: queryParams
      ) { @MainActor url in
        try await withCheckedThrowingContinuation { [configuration] continuation in
          guard let callbackScheme = (configuration.redirectToURL ?? redirectTo)?.scheme else {
            preconditionFailure(
              "Please, provide a valid redirect URL, either thorugh `redirectTo` param, or globally thorugh `AuthClient.Configuration.redirectToURL`."
            )
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
              fatalError("Expected url or error, but got none.")
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

  /// Handles an incoming URL received by the app.
  ///
  /// ## Usage example:
  ///
  /// ### UIKit app lifecycle
  ///
  /// In your `AppDelegate.swift`:
  ///
  /// ```swift
  /// public func application(
  ///   _ application: UIApplication,
  ///   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  /// ) -> Bool {
  ///   if let url = launchOptions?[.url] as? URL {
  ///     supabase.auth.handle(url)
  ///   }
  ///
  ///   return true
  /// }
  ///
  /// func application(
  ///   _ app: UIApplication,
  ///   open url: URL,
  ///   options: [UIApplication.OpenURLOptionsKey: Any]
  /// ) -> Bool {
  ///   supabase.auth.handle(url)
  ///   return true
  /// }
  /// ```
  ///
  /// ### UIKit app lifecycle with scenes
  ///
  /// In your `SceneDelegate.swift`:
  ///
  /// ```swift
  /// func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
  ///   guard let url = URLContexts.first?.url else { return }
  ///   supabase.auth.handle(url)
  /// }
  /// ```
  ///
  /// ### SwiftUI app lifecycle
  ///
  /// In your `AppDelegate.swift`:
  ///
  /// ```swift
  /// SomeView()
  ///   .onOpenURL { url in
  ///     supabase.auth.handle(url)
  ///   }
  /// ```
  public func handle(_ url: URL) async throws(AuthError) {
    do {
      try await session(from: url)
    } catch {
      configuration.logger?.error("Failure loading session from url '\(url)' error: \(error)")
      throw error
    }
  }

  /// Gets the session data from a OAuth2 callback URL.
  @discardableResult
  public func session(from url: URL) async throws(AuthError) -> Session {
    configuration.logger?.debug("Received URL: \(url)")

    let params = extractParams(from: url)

    return try await wrappingError(or: mapToAuthError) {
      switch self.configuration.flowType {
      case .implicit:
        guard self.isImplicitGrantFlow(params: params) else {
          throw AuthError.implicitGrantRedirect(
            message: "Not a valid implicit grant flow URL: \(url)"
          )
        }
        return try await self.handleImplicitGrantFlow(params: params)

      case .pkce:
        guard self.isPKCEFlow(params: params) else {
          throw AuthError.pkceGrantCodeExchange(message: "Not a valid PKCE flow URL: \(url)")
        }
        return try await self.handlePKCEFlow(params: params)
      }
    }
  }

  private func handleImplicitGrantFlow(params: [String: String]) async throws -> Session {
    precondition(configuration.flowType == .implicit, "Method only allowed for implicit flow.")

    if let errorDescription = params["error_description"] {
      throw AuthError.implicitGrantRedirect(
        message: errorDescription.replacingOccurrences(of: "+", with: " ")
      )
    }

    guard
      let accessToken = params["access_token"],
      let expiresIn = params["expires_in"].flatMap(TimeInterval.init),
      let refreshToken = params["refresh_token"],
      let tokenType = params["token_type"]
    else {
      throw AuthError.implicitGrantRedirect(message: "No session defined in URL")
    }

    let expiresAt = params["expires_at"].flatMap(TimeInterval.init)
    let providerToken = params["provider_token"]
    let providerRefreshToken = params["provider_refresh_token"]

    let user = try await execute(
      self.url.appendingPathComponent("user"),
      method: .get,
      headers: [.authorization(bearerToken: accessToken)]
    )
    .serializingDecodable(User.self, decoder: JSONDecoder.auth)
    .value

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

    await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)

    if let type = params["type"], type == "recovery" {
      eventEmitter.emit(.passwordRecovery, session: session)
    }

    return session
  }

  private func handlePKCEFlow(params: [String: String]) async throws -> Session {
    precondition(configuration.flowType == .pkce, "Method only allowed for PKCE flow.")

    if params["error"] != nil || params["error_description"] != nil || params["error_code"] != nil {
      throw AuthError.pkceGrantCodeExchange(
        message: params["error_description"]?.replacingOccurrences(of: "+", with: " ")
          ?? "Error in URL with unspecified error_description.",
        error: params["error"] ?? "unspecified_error",
        code: params["error_code"] ?? "unspecified_code"
      )
    }

    guard let code = params["code"] else {
      throw AuthError.pkceGrantCodeExchange(message: "No code detected.")
    }

    return try await exchangeCodeForSession(authCode: code)
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
  public func setSession(accessToken: String, refreshToken: String) async throws(AuthError)
    -> Session
  {
    let now = date()
    var expiresAt = now
    var hasExpired = true
    var session: Session

    let jwt = JWT.decodePayload(accessToken)
    if let exp = jwt?["exp"] as? TimeInterval {
      expiresAt = Date(timeIntervalSince1970: exp)
      hasExpired = expiresAt <= now
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

    await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)
    return session
  }

  /// Signs out the current user, if there is a logged in user.
  ///
  /// If using ``SignOutScope/others`` scope, no ``AuthChangeEvent/signedOut`` event is fired.
  /// - Parameter scope: Specifies which sessions should be logged out.
  public func signOut(scope: SignOutScope = .global) async throws(AuthError) {
    guard let accessToken = currentSession?.accessToken else {
      configuration.logger?.warning("signOut called without a session")
      return
    }

    if scope != .others {
      await sessionManager.remove()
      eventEmitter.emit(.signedOut, session: nil)
    }

    do {
      try await wrappingError(or: mapToAuthError) {
        _ = try await self.execute(
          self.url.appendingPathComponent("logout"),
          method: .post,
          headers: [.authorization(bearerToken: accessToken)],
          query: ["scope": scope.rawValue]
        )
        .serializingData()
        .value
      }
    } catch let AuthError.api(_, _, _, response)
      where [404, 403, 401].contains(response.statusCode)
    {
      // ignore 404s since user might not exist anymore
      // ignore 401s, and 403s since an invalid or expired JWT should sign out the current session.
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
  ) async throws(AuthError) -> AuthResponse {
    try await _verifyOTP(
      query: (redirectTo ?? configuration.redirectToURL).map {
        ["redirect_to": $0.absoluteString]
      },
      body: .email(
        VerifyEmailOTPParams(
          email: email,
          token: token,
          type: type,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      )
    )
  }

  /// Log in an user given a User supplied OTP received via mobile.
  @discardableResult
  public func verifyOTP(
    phone: String,
    token: String,
    type: MobileOTPType,
    captchaToken: String? = nil
  ) async throws(AuthError) -> AuthResponse {
    try await _verifyOTP(
      body: .mobile(
        VerifyMobileOTPParams(
          phone: phone,
          token: token,
          type: type,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      )
    )
  }

  /// Log in an user given a token hash received via email.
  @discardableResult
  public func verifyOTP(
    tokenHash: String,
    type: EmailOTPType
  ) async throws(AuthError) -> AuthResponse {
    try await _verifyOTP(
      body: .tokenHash(VerifyTokenHashParams(tokenHash: tokenHash, type: type))
    )
  }

  private func _verifyOTP(
    query: Parameters? = nil,
    body: VerifyOTPParams
  ) async throws(AuthError) -> AuthResponse {
    let response = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("verify"),
        method: .post,
        query: query,
        body: body
      )
      .serializingDecodable(AuthResponse.self, decoder: JSONDecoder.auth)
      .value
    }

    if let session = response.session {
      await sessionManager.update(session)
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
  ) async throws(AuthError) {
    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("resend"),
        method: .post,
        query: (emailRedirectTo ?? self.configuration.redirectToURL).map {
          ["redirect_to": $0.absoluteString]
        },
        body: ResendEmailParams(
          type: type,
          email: email,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      )
      .serializingData()
      .value
    }
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
  ) async throws(AuthError) -> ResendMobileResponse {
    return try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("resend"),
        method: .post,
        body: ResendMobileParams(
          type: type,
          phone: phone,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
        )
      )
      .serializingDecodable(ResendMobileResponse.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Sends a re-authentication OTP to the user's email or phone number.
  public func reauthenticate() async throws(AuthError) {
    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("reauthenticate"),
        method: .get,
        headers: [
          .authorization(bearerToken: try await self.session.accessToken)
        ]
      )
      .serializingData()
      .value
    }
  }

  /// Gets the current user details if there is an existing session.
  /// - Parameter jwt: Takes in an optional access token jwt. If no jwt is provided, user() will
  /// attempt to get the jwt from the current session.
  ///
  /// Should be used only when you require the most current user data. For faster results, ``currentUser`` is recommended.
  public func user(jwt: String? = nil) async throws(AuthError) -> User {
    return try await wrappingError(or: mapToAuthError) {
      if let jwt {
        return try await self.execute(
          self.url.appendingPathComponent("user"),
          headers: [
            .authorization(bearerToken: jwt)
          ]
        )
        .serializingDecodable(User.self, decoder: JSONDecoder.auth)
        .value

      }

      return try await self.execute(
        self.url.appendingPathComponent("user"),
        headers: [
          .authorization(bearerToken: try await self.session.accessToken)
        ]
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Updates user data, if there is a logged in user.
  @discardableResult
  public func update(user: UserAttributes, redirectTo: URL? = nil) async throws(AuthError) -> User {
    var user = user

    if user.email != nil {
      let (codeChallenge, codeChallengeMethod) = prepareForPKCE()
      user.codeChallenge = codeChallenge
      user.codeChallengeMethod = codeChallengeMethod
    }

    return try await wrappingError(or: mapToAuthError) { [user] in
      var session = try await self.sessionManager.session()
      let updatedUser = try await self.execute(
        self.url.appendingPathComponent("user"),
        method: .put,
        query: (redirectTo ?? self.configuration.redirectToURL).map {
          ["redirect_to": $0.absoluteString]
        },
        body: user
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value

      session.user = updatedUser
      await self.sessionManager.update(session)
      self.eventEmitter.emit(.userUpdated, session: session)
      return updatedUser
    }
  }

  /// Gets all the identities linked to a user.
  public func userIdentities() async throws(AuthError) -> [UserIdentity] {
    try await user().identities ?? []
  }

  /// Link an identity to the current user using an ID token.
  @discardableResult
  public func linkIdentityWithIdToken(
    credentials: OpenIDConnectCredentials
  ) async throws -> Session {
    var credentials = credentials
    credentials.linkIdentity = true

    let currentSession = try await session
    let newSession = try await wrappingError(or: mapToAuthError) { [credentials] in
      try await self.execute(
        self.url.appendingPathComponent("token"),
        method: .post,
        headers: ["Authorization": "Bearer \(currentSession.accessToken)"],
        query: ["grant_type": "id_token"],
        body: credentials
      )
      .serializingDecodable(Session.self, decoder: JSONDecoder.auth)
      .value
    }

    await sessionManager.update(newSession)
    eventEmitter.emit(.userUpdated, session: newSession)

    return newSession
  }

  /// Links an OAuth identity to an existing user.
  ///
  /// This method supports the PKCE flow.
  ///
  /// - Parameters:
  ///   - provider: The provider you want to link the user with.
  ///   - scopes: A space-separated list of scopes granted to the OAuth application.
  ///   - redirectTo: A URL to send the user to after they are confirmed.
  ///   - queryParams: Additional query parameters to use.
  ///   - launchURL: Custom launch URL logic.
  public func linkIdentity(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = [],
    launchURL: @MainActor (_ url: URL) -> Void
  ) async throws(AuthError) {
    let response = try await getLinkIdentityURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams
    )

    await launchURL(response.url)
  }

  /// Links an OAuth identity to an existing user.
  ///
  /// This method supports the PKCE flow.
  ///
  /// - Parameters:
  ///   - provider: The provider you want to link the user with.
  ///   - scopes: A space-separated list of scopes granted to the OAuth application.
  ///   - redirectTo: A URL to send the user to after they are confirmed.
  ///   - queryParams: Additional query parameters to use.
  ///
  /// - Note: This method opens the URL using the default URL opening mechanism for the platform, if you with to provide your own URL opening logic use ``linkIdentity(provider:scopes:redirectTo:queryParams:launchURL:)``.
  public func linkIdentity(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) async throws(AuthError) {
    try await linkIdentity(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams,
      launchURL: { url in
        Task {
          await self.urlOpener.open(url)
        }
      }
    )
  }

  /// Returns the URL to link the user's identity with an OAuth provider.
  ///
  /// This method supports the PKCE flow.
  ///
  /// - Parameters:
  ///   - provider: The provider you want to link the user with.
  ///   - scopes: A space-separated list of scopes granted to the OAuth application.
  ///   - redirectTo: A URL to send the user to after they are confirmed.
  ///   - queryParams: Additional query parameters to use.
  public func getLinkIdentityURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) async throws(AuthError) -> OAuthResponse {
    try await wrappingError(or: mapToAuthError) {
      let url = try self.getURLForProvider(
        url: self.url.appendingPathComponent("user/identities/authorize"),
        provider: provider,
        scopes: scopes,
        redirectTo: redirectTo,
        queryParams: queryParams,
        skipBrowserRedirect: true
      )

      struct Response: Codable {
        let url: URL
      }

      let response = try await self.execute(
        url,
        method: .get,
        headers: [
          .authorization(bearerToken: try await self.session.accessToken)
        ]
      )
      .serializingDecodable(Response.self, decoder: JSONDecoder.auth)
      .value

      return OAuthResponse(provider: provider, url: response.url)
    }
  }

  /// Unlinks an identity from a user by deleting it. The user will no longer be able to sign in
  /// with that identity once it's unlinked.
  public func unlinkIdentity(_ identity: UserIdentity) async throws(AuthError) {
    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("user/identities/\(identity.identityId)"),
        method: .delete,
        headers: [
          .authorization(bearerToken: try await self.session.accessToken)
        ]
      )
      .serializingData()
      .value
    }
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws(AuthError) {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await wrappingError(or: mapToAuthError) {
      try await self.execute(
        self.url.appendingPathComponent("recover"),
        method: .post,
        query: (redirectTo ?? self.configuration.redirectToURL).map {
          ["redirect_to": $0.absoluteString]
        },
        body: RecoverParams(
          email: email,
          gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
          codeChallenge: codeChallenge,
          codeChallengeMethod: codeChallengeMethod
        )
      )
      .serializingData()
      .value
    }
  }

  /// Refresh and return a new session, regardless of expiry status.
  /// - Parameter refreshToken: The optional refresh token to use for refreshing the session. If
  /// none is provided then this method tries to load the refresh token from the current session.
  /// - Returns: A new session.
  @discardableResult
  public func refreshSession(refreshToken: String? = nil) async throws(AuthError) -> Session {
    guard let refreshToken = refreshToken ?? currentSession?.refreshToken else {
      throw AuthError.sessionMissing
    }

    return try await wrappingError(or: mapToAuthError) {
      try await self.sessionManager.refreshSession(refreshToken)
    }
  }

  /// Starts an auto-refresh process in the background. The session is checked every few seconds. Close to the time of expiration a process is started to refresh the session. If refreshing fails it will be retried for as long as necessary.
  ///
  /// If you set ``Configuration/autoRefreshToken`` you don't need to call this function, it will be called for you.
  public func startAutoRefresh() {
    Task { await sessionManager.startAutoRefresh() }
  }

  /// Stops an active auto refresh process running in the background (if any).
  public func stopAutoRefresh() {
    Task { await sessionManager.stopAutoRefresh() }
  }

  private func emitInitialSession(forToken token: ObservationToken) async {
    let session = try? await session
    eventEmitter.emit(.initialSession, session: session, token: token)
  }

  private func prepareForPKCE() -> (
    codeChallenge: String?, codeChallengeMethod: String?
  ) {
    guard configuration.flowType == .pkce else {
      return (nil, nil)
    }

    let codeVerifier = pkce.generateCodeVerifier()
    setCodeVerifier(codeVerifier)

    let codeChallenge = pkce.generateCodeChallenge(codeVerifier)
    let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

    return (codeChallenge, codeChallengeMethod)
  }

  private func isImplicitGrantFlow(params: [String: String]) -> Bool {
    params["access_token"] != nil || params["error_description"] != nil
  }

  private func isPKCEFlow(params: [String: String]) -> Bool {
    let currentCodeVerifier = getCodeVerifier()
    return params["code"] != nil || params["error_description"] != nil || params["error"] != nil
      || params["error_code"] != nil && currentCodeVerifier != nil
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
        url: url,
        resolvingAgainstBaseURL: false
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

    if let redirectTo = redirectTo ?? self.configuration.redirectToURL {
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
