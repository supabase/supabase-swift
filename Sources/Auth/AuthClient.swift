import ConcurrencyExtras
public import Foundation
import IssueReporting
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

typealias AuthClientID = Int

private let jwksTTL: TimeInterval = 10 * 60

private struct CachedJWKS {
  let jwks: JWKS
  let cachedAt: Date
}

/// Global JWKS cache shared across all clients with the same storage key.
/// This is especially useful for shared-memory execution environments such as
/// AWS Lambda or serverless functions. Regardless of how many clients are created,
/// if they share the same storage key they will use the same JWKS cache,
/// significantly speeding up claims() with asymmetric JWTs.
private actor GlobalJWKSCache {
  private var cache: [String: CachedJWKS] = [:]

  func get(for key: String) -> CachedJWKS? {
    cache[key]
  }

  func set(_ value: CachedJWKS, for key: String) {
    cache[key] = value
  }
}

private let globalJWKSCache = GlobalJWKSCache()

/// The primary interface to Supabase Auth.
///
/// Use `AuthClient` to sign users up, sign them in, manage sessions, and subscribe to
/// authentication-state changes. It is `Sendable`: one instance can be shared across tasks and
/// actors, and every member that does not need the network is synchronous.
///
/// ```swift
/// let auth = AuthClient(
///   url: URL(string: "https://<project>.supabase.co/auth/v1")!,
///   headers: ["apikey": "<publishable-key>"],
///   localStorage: KeychainLocalStorage()
/// )
///
/// // Sign in
/// let session = try await auth.signIn(email: "user@example.com", password: "secret")
///
/// // Listen for state changes
/// for await (event, session) in auth.authStateChanges {
///   print(event, session?.user.email ?? "signed out")
/// }
/// ```
///
/// ## Topics
///
/// ### Observing state
/// - ``onAuthStateChange(_:)``
/// - ``authStateChanges``
/// - ``currentSession``
/// - ``currentUser``
/// - ``session``
///
/// ### Signing up
/// - ``signUp(email:password:data:redirectTo:captchaToken:)``
/// - ``signUp(phone:password:channel:data:captchaToken:)``
/// - ``signInAnonymously(data:captchaToken:)``
///
/// ### Signing in
/// - ``signIn(email:password:captchaToken:)``
/// - ``signIn(phone:password:captchaToken:)``
/// - ``signInWithIdToken(credentials:)``
/// - ``signInWithOTP(email:redirectTo:shouldCreateUser:data:captchaToken:)``
/// - ``signInWithOTP(phone:channel:shouldCreateUser:data:captchaToken:)``
/// - ``signInWithSSO(domain:redirectTo:captchaToken:)``
/// - ``signInWithSSO(providerId:redirectTo:captchaToken:)``
/// - ``signInWithOAuth(provider:redirectTo:scopes:queryParams:launchFlow:)``
///
/// ### Session management
/// - ``exchangeCodeForSession(authCode:flowId:)``
/// - ``session(from:)``
/// - ``setSession(accessToken:refreshToken:)``
/// - ``refreshSession(refreshToken:)``
/// - ``refreshSessionIfNeeded()``
/// - ``startAutoRefresh()``
/// - ``stopAutoRefresh()``
///
/// ### Signing out
/// - ``signOut(scope:)``
///
/// ### User management
/// - ``user(jwt:)``
/// - ``update(user:redirectTo:)``
/// - ``verifyOTP(email:token:type:redirectTo:captchaToken:)``
/// - ``verifyOTP(phone:token:type:captchaToken:)``
/// - ``verifyOTP(tokenHash:type:)``
/// - ``resend(email:type:emailRedirectTo:captchaToken:)``
/// - ``resend(phone:type:captchaToken:)``
/// - ``reauthenticate()``
/// - ``resetPasswordForEmail(_:redirectTo:captchaToken:)``
///
/// ### Identities
/// - ``userIdentities()``
/// - ``linkIdentity(provider:scopes:redirectTo:queryParams:launchURL:)``
/// - ``linkIdentity(provider:scopes:redirectTo:queryParams:)``
/// - ``linkIdentityWithIdToken(credentials:)``
/// - ``linkIdentityURL(provider:scopes:redirectTo:queryParams:)``
/// - ``unlinkIdentity(_:)``
///
/// ### JWT claims
/// - ``claims(jwt:options:)``
///
/// ### Namespaces
/// - ``mfa``
/// - ``admin``
/// - ``oauthServer``
///
/// ### Notifications
/// - ``didChangeAuthStateNotification``
/// - ``authChangeEventInfoKey``
/// - ``authChangeSessionInfoKey``
public final class AuthClient: Sendable {
  private static let _globalClientID = LockIsolated(0)

  private static func nextClientID() -> AuthClientID {
    _globalClientID.withValue { value in
      value += 1
      return value
    }
  }

  let clientID: AuthClientID

  let dependencies: Dependencies

  private var api: SessionAPIClient { dependencies.sessionAPI }
  private var authAPI: AuthAPI { dependencies.authAPI }

  var configuration: AuthClient.Configuration { dependencies.configuration }

  private var codeVerifierStorage: CodeVerifierStorage {
    dependencies.codeVerifierStorage
  }

  private var date: @Sendable () -> Date { dependencies.date }
  private var sessionManager: SessionManager { dependencies.sessionManager }
  private var sessionStore: SessionStore { dependencies.sessionStore }
  private var logger: Logging.Logger {
    dependencies.configuration.logger
  }
  private var pkce: PKCE { dependencies.pkce }

  /// Loads the stored session when the first read failed, then posts
  /// ``didChangeAuthStateNotification`` for each change, for as long as the client lives.
  private let notificationTask: Task<Void, Never>

  private let lifecycleTask: Task<Void, Never>

  /// Returns the session, refreshing it if necessary.
  ///
  /// Throws an error of kind ``AuthError/Kind-swift.struct/sessionMissing`` when no session is
  /// stored, and of kind ``AuthError/Kind-swift.struct/sessionInvalidated`` when the server
  /// rejects the refresh of an expired session.
  ///
  /// When storage could not be read yet, each call reads it again, as do
  /// ``refreshSessionIfNeeded()``, requests that send the session's access token, and each new
  /// ``onAuthStateChange(_:)`` or ``authStateChanges`` subscription. While the device is locked it
  /// throws an error of kind ``AuthError/Kind-swift.struct/storageUnavailable``. On iOS, iPadOS,
  /// tvOS, visionOS, and Mac Catalyst the client also reads storage when protected data becomes
  /// available. On watchOS and macOS, only those calls read storage again. A missing Keychain
  /// entitlement throws an error of kind
  /// ``AuthError/Kind-swift.struct/storageMisconfigured``.
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Returns the current session, if any.
  ///
  /// The session returned by this property may be expired. Use ``session`` for a session that is guaranteed to be valid.
  public var currentSession: Session? {
    sessionStore.currentSession
  }

  /// Returns the current user, if any.
  ///
  /// The user returned by this property may be outdated. Use ``user(jwt:)`` method to get an up-to-date user instance.
  public var currentUser: User? {
    currentSession?.user
  }

  /// Namespace for accessing multi-factor authentication API.
  public var mfa: AuthMFA {
    AuthMFA(client: self)
  }

  /// Namespace for the GoTrue admin methods.
  /// - Warning: This methods requires `secret` key, be careful to never expose `secret`
  /// key in the client.
  public var admin: AuthAdmin {
    AuthAdmin(authAPI: dependencies.authAPI, api: dependencies.api)
  }

  /// Namespace for the OAuth 2.1 authorization server consent and grant-management API.
  public var oauthServer: AuthOAuthServer {
    AuthOAuthServer(client: self)
  }

  /// Initializes a AuthClient with a specific configuration.
  ///
  /// - Parameters:
  ///   - configuration: The client configuration.
  public convenience init(configuration: Configuration) {
    self.init(configuration: configuration, date: { Date() }, pkce: .live, platform: .live)
  }

  /// Test seam: pins the clock, the PKCE material, and the platform at construction.
  init(
    configuration: Configuration,
    date: @escaping @Sendable () -> Date,
    pkce: PKCE,
    platform: AuthPlatform
  ) {
    let clientID = AuthClient.nextClientID()
    self.clientID = clientID

    let logger: Logging.Logger = {
      var logger = configuration.logger
      logger[metadataKey: "client_id"] = "\(clientID)"
      return logger
    }()

    let dependencies = Dependencies.live(
      configuration: configuration,
      logger: logger,
      date: date,
      pkce: pkce,
      platform: platform
    )
    self.dependencies = dependencies
    notificationTask = Self.postAuthStateChangeNotifications(
      sessionStore: dependencies.sessionStore, logger: logger)

    let autoRefresh = dependencies.autoRefresh
    lifecycleTask = Self.observeAppLifecycle(
      platform: platform,
      sessionStore: dependencies.sessionStore,
      autoRefresh: configuration.observesAppLifecycle ? autoRefresh : nil
    )
    Task { await autoRefresh.apply() }
  }

  deinit {
    notificationTask.cancel()
    lifecycleTask.cancel()
    let autoRefresh = dependencies.autoRefresh
    Task { await autoRefresh.stop() }
  }

  private static func observeAppLifecycle(
    platform: AuthPlatform,
    sessionStore: SessionStore,
    autoRefresh: AutoRefreshController?
  ) -> Task<Void, Never> {
    Task {
      for await event in await platform.lifecycleEvents() {
        if event == .protectedDataDidBecomeAvailable {
          try? await sessionStore.load()
        }
        await autoRefresh?.handle(event)
      }
    }
  }

  /// Listen for auth state changes.
  /// - Parameter listener: Block that executes when a new event is emitted.
  /// - Returns: A handle that can be used to manually unsubscribe.
  ///
  /// - Note: The session emitted in the ``AuthChangeEvent/initialSession`` event may have expired
  /// since the last launch, so check ``Session/isExpired``. With
  /// ``Configuration/autoRefresh`` set to ``AutoRefreshPolicy/automatic``, expect a
  /// ``AuthChangeEvent/tokenRefreshed`` after it.
  @discardableResult
  public func onAuthStateChange(
    _ listener: @escaping AuthStateChangeListener
  ) async -> some AuthStateChangeListenerRegistration {
    try? await sessionStore.load()

    let (initialSessionDelivered, delivered) = AsyncStream<Never>.makeStream()
    let task = Self.observeAuthStateChanges(
      sessionStore: sessionStore
    ) { event, session in
      listener(event, session)
      delivered.finish()
    }

    // While storage stays unreadable there is no initial session to wait for.
    if sessionStore.currentStatus != .loading {
      for await _ in initialSessionDelivered {}
    }
    return ObservationToken { task.cancel() }
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
    >.makeStream(bufferingPolicy: .unbounded)

    let task = Self.observeAuthStateChanges(
      sessionStore: sessionStore
    ) { event, session in
      continuation.yield((event, session))
    }

    continuation.onTermination = { _ in
      task.cancel()
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
    data: [String: JSONValue]? = nil,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _signUp(
      authAPI.signUp(
        email: email,
        password: password,
        data: data,
        redirectTo: redirectTo,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
      )
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
    data: [String: JSONValue]? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _signUp(
      authAPI.signUp(
        phone: phone,
        password: password,
        channel: channel,
        data: data,
        captchaToken: captchaToken
      )
    )
  }

  private func _signUp(_ request: AuthRequest<AuthResponse>) async throws -> AuthResponse {
    let response = try await api.execute(request)

    if let session = response.session {
      try await sessionStore.commit(.signedIn(session, event: .signedIn))
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
  ) async throws -> Session {
    try await _signIn(
      authAPI.signInWithPassword(email: email, password: password, captchaToken: captchaToken)
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
  ) async throws -> Session {
    try await _signIn(
      authAPI.signInWithPassword(phone: phone, password: password, captchaToken: captchaToken)
    )
  }

  /// Allows signing in with an ID token issued by certain supported providers.
  /// The ID token is verified for validity and a new session is established.
  @discardableResult
  public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session {
    try await _signIn(authAPI.signInWithIdToken(credentials: credentials))
  }

  /// Signs in a user via a signed Sign in with Ethereum (EIP-4361) or Sign in with Solana message.
  ///
  /// The app is responsible for building the message and obtaining the signature from the user's
  /// wallet (e.g. via a WalletConnect session or native wallet SDK) before calling this method.
  ///
  /// ```swift
  /// let session = try await client.auth.signInWithWeb3(
  ///   credentials: Web3Credentials(
  ///     chain: .ethereum,
  ///     message: siweMessage,
  ///     signature: signatureHex
  ///   )
  /// )
  /// ```
  @discardableResult
  public func signInWithWeb3(credentials: Web3Credentials) async throws -> Session {
    try await _signIn(authAPI.signInWithWeb3(credentials: credentials))
  }

  /// Creates a new anonymous user.
  /// - Parameters:
  ///   - data: A custom data object to store the user's metadata. This maps to the
  /// `auth.users.raw_user_meta_data` column. The `data` should be a JSON object that includes
  /// user-specific info, such as their first and last name.
  ///   - captchaToken: Verification token received when the user completes the captcha.
  @discardableResult
  public func signInAnonymously(
    data: [String: JSONValue]? = nil,
    captchaToken: String? = nil
  ) async throws -> Session {
    try await _signIn(authAPI.signInAnonymously(data: data, captchaToken: captchaToken))
  }

  private func _signIn(_ request: AuthRequest<Session>) async throws -> Session {
    let session = try await api.execute(request)

    try await sessionStore.commit(.signedIn(session, event: .signedIn))

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
    data: [String: JSONValue]? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await api.execute(
      authAPI.signInWithOTP(
        email: email,
        redirectTo: redirectTo,
        shouldCreateUser: shouldCreateUser,
        data: data,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
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
  /// - Note: You need to configure a WhatsApp sender on Twilio if you are using phone sign in with the `whatsapp` channel.
  public func signInWithOTP(
    phone: String,
    channel: MessagingChannel = .sms,
    shouldCreateUser: Bool = true,
    data: [String: JSONValue]? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await api.execute(
      authAPI.signInWithOTP(
        phone: phone,
        channel: channel,
        shouldCreateUser: shouldCreateUser,
        data: data,
        captchaToken: captchaToken
      )
    )
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
  ) async throws -> SSOResponse {
    try await api.execute(
      authAPI.signInWithSSO(
        domain: domain,
        redirectTo: redirectTo,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
      )
    )
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
    try await api.execute(
      authAPI.signInWithSSO(
        providerId: providerId,
        redirectTo: redirectTo,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
      )
    )
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  /// - Parameters:
  ///   - authCode: The auth code received from the PKCE callback.
  ///   - flowId: The id of the flow that generated `authCode`, as returned by
  /// ``signInWithOAuth(provider:redirectTo:scopes:queryParams:launchFlow:)`` or
  /// ``linkIdentityURL(provider:scopes:redirectTo:queryParams:)``. Pass this when several
  /// PKCE flows may be pending at once, so the correct code verifier is used. When `nil`, the
  /// most recently started flow's verifier is used.
  public func exchangeCodeForSession(authCode: String, flowId: String? = nil) async throws
    -> Session
  {
    let codeVerifier = codeVerifierStorage.get(flowId)

    if codeVerifier == nil {
      logger.error(
        "code verifier not found, a code verifier should exist when calling this method."
      )
    }

    let session = try await api.execute(
      authAPI.exchangeCodeForSession(authCode: authCode, codeVerifier: codeVerifier)
    )

    codeVerifierStorage.remove(flowId)

    try await sessionStore.commit(.signedIn(session, event: .signedIn))

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
  public func oauthSignInURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) throws -> URL {
    try authAPI.authorizeURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams,
      pkce: prepareForPKCE().challenge
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
    let (pkce, flowId) = prepareForPKCE()
    let url = try authAPI.authorizeURL(
      provider: provider,
      scopes: scopes,
      redirectTo: Self.oauthRedirectURL(
        redirectTo: redirectTo,
        configured: configuration.redirectToURL
      ),
      queryParams: queryParams,
      pkce: pkce
    )

    let resultURL = try await launchFlow(url)

    return try await session(from: resultURL, flowId: flowId)
  }

  /// The redirect an OAuth flow will actually use: a per-call `redirectTo` overrides the
  /// client-wide ``Configuration/redirectToURL``.
  ///
  /// Both halves of the flow have to agree on this — the authorize request tells the provider
  /// where to send the user, and `ASWebAuthenticationSession` is told which scheme to listen
  /// on. They are resolved in different places, and writing the rule out twice is exactly how
  /// they drifted apart and stopped agreeing (SDK-1873), so it lives here once instead.
  static func oauthRedirectURL(redirectTo: URL?, configured: URL?) -> URL? {
    redirectTo ?? configured
  }

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
  public func handle(_ url: URL) {
    Task {
      do {
        try await session(from: url)
      } catch {
        logger.error("Failure loading session from url '\(url)' error: \(error)")
      }
    }
  }

  /// Gets the session data from a OAuth2 callback URL.
  @discardableResult
  public func session(from url: URL) async throws -> Session {
    try await session(from: url, flowId: nil)
  }

  /// Gets the session data from a OAuth2 callback URL.
  /// - Parameter flowId: The id of the PKCE flow that produced this callback, when known ahead
  /// of time (e.g. the flow that was just launched by ``signInWithOAuth(provider:redirectTo:scopes:queryParams:launchFlow:)``).
  /// `nil` falls back to the most recently started flow's verifier.
  private func session(from url: URL, flowId: String?) async throws -> Session {
    logger.debug("Received URL: \(url)")

    let params = extractParams(from: url)

    switch configuration.flowType {
    case .implicit:
      guard isImplicitGrantFlow(params: params) else {
        throw AuthError.oauthFlowFailed("Not a valid implicit grant flow URL: \(url)")
      }
      return try await handleImplicitGrantFlow(params: params)

    case .pkce:
      guard isPKCEFlow(params: params) else {
        throw AuthError.oauthFlowFailed("Not a valid PKCE flow URL: \(url)")
      }
      return try await handlePKCEFlow(params: params, flowId: flowId)
    }
  }

  /// Only reached from ``session(from:)``, under `case .implicit` of its switch on
  /// `configuration.flowType`, which is what guarantees the flow type here.
  private func handleImplicitGrantFlow(params: [String: String]) async throws -> Session {
    if let errorMessage = params["error_description"] ?? params["error"] {
      throw AuthError.oauthFlowFailed(errorMessage)
    }

    guard
      let accessToken = params["access_token"],
      let expiresIn = params["expires_in"].flatMap(TimeInterval.init),
      let refreshToken = params["refresh_token"],
      let tokenType = params["token_type"]
    else {
      throw AuthError.oauthFlowFailed("No session defined in URL")
    }

    let expiresAt = params["expires_at"].flatMap(TimeInterval.init)
    let providerToken = params["provider_token"]
    let providerRefreshToken = params["provider_refresh_token"]

    let user = try await api.execute(
      authAPI.user(accessToken: accessToken, tokenType: tokenType),
      for: sessionOwnership(ofAccessToken: accessToken)
    )

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

    try await sessionStore.commit(.signedIn(session, event: .signedIn))

    if let type = params["type"], type == "recovery" {
      try await sessionStore.commit(.signedIn(session, event: .passwordRecovery))
    }

    return session
  }

  /// Only reached from ``session(from:)``, under `case .pkce` of its switch on
  /// `configuration.flowType`, which is what guarantees the flow type here.
  private func handlePKCEFlow(params: [String: String], flowId: String?) async throws -> Session {
    if params["error"] != nil || params["error_description"] != nil || params["error_code"] != nil {
      let oauthError = params["error"] ?? "unspecified_error"
      let description =
        params["error_description"] ?? "Error in URL with unspecified error_description."
      throw AuthError.oauthFlowFailed(
        "\(oauthError): \(description)",
        errorCode: params["error_code"].map { ErrorCode($0) } ?? .unknown
      )
    }

    guard let code = params["code"] else {
      throw AuthError.oauthFlowFailed("No code detected.")
    }

    return try await exchangeCodeForSession(authCode: code, flowId: flowId)
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

    try await sessionStore.commit(.signedIn(session, event: .signedIn))
    return session
  }

  /// Signs out the current user, if there is a logged in user.
  ///
  /// If using ``SignOutScope/others`` scope, no ``AuthChangeEvent/signedOut`` event is fired.
  /// - Parameter scope: Specifies which sessions should be logged out.
  public func signOut(scope: SignOutScope = .global) async throws {
    guard let session = currentSession else {
      configuration.logger.warning("signOut called without a session")
      return
    }

    if scope != .others {
      try await sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
    }

    do {
      try await api.execute(
        authAPI.signOut(accessToken: session.accessToken, scope: scope),
        for: .snapshot(session)
      )
    } catch let error as AuthError
      where error.kind == .sessionInvalidated
      || error.kind == .server && [404, 403, 401].contains(error.response?.statusCode ?? 0)
    {}
  }

  /// Log in an user given a User supplied OTP received via email.
  @discardableResult
  public func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> VerifyOTPResponse {
    try await _verifyOTP(
      authAPI.verifyOTP(
        email: email,
        token: token,
        type: type,
        redirectTo: redirectTo,
        captchaToken: captchaToken
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
  ) async throws -> VerifyOTPResponse {
    try await _verifyOTP(
      authAPI.verifyOTP(phone: phone, token: token, type: type, captchaToken: captchaToken)
    )
  }

  /// Log in an user given a token hash received via email.
  @discardableResult
  public func verifyOTP(
    tokenHash: String,
    type: EmailOTPType
  ) async throws -> VerifyOTPResponse {
    try await _verifyOTP(authAPI.verifyOTP(tokenHash: tokenHash, type: type))
  }

  private func _verifyOTP(
    _ request: AuthRequest<VerifyOTPResponse>
  ) async throws -> VerifyOTPResponse {
    let response = try await api.execute(request)

    if let session = response.session {
      try await sessionStore.commit(.signedIn(session, event: .signedIn))
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
    try await api.execute(
      authAPI.resend(
        email: email,
        type: type,
        redirectTo: emailRedirectTo,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
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
    try await api.execute(authAPI.resend(phone: phone, type: type, captchaToken: captchaToken))
  }

  /// Sends a re-authentication OTP to the user's email or phone number.
  public func reauthenticate() async throws {
    try await api.authorizedExecute { authAPI.reauthenticate(accessToken: $0) }
  }

  /// Gets the current user details if there is an existing session.
  /// - Parameter jwt: Takes in an optional access token jwt. If no jwt is provided, user() will
  /// attempt to get the jwt from the current session.
  ///
  /// Should be used only when you require the most current user data. For faster results, ``currentUser`` is recommended.
  public func user(jwt: String? = nil) async throws -> User {
    if let jwt {
      return try await api.execute(
        authAPI.user(accessToken: jwt), for: sessionOwnership(ofAccessToken: jwt))
    }

    return try await api.authorizedExecute { authAPI.user(accessToken: $0) }
  }

  private func sessionOwnership(ofAccessToken accessToken: String) -> SessionOwnership {
    guard let stored = currentSession, stored.accessToken == accessToken else { return .unscoped }
    return .snapshot(stored)
  }

  /// Updates user data, if there is a logged in user.
  @discardableResult
  public func update(user: UserAttributes, redirectTo: URL? = nil) async throws -> User {
    let pkce = user.email != nil ? prepareForPKCE().challenge : nil

    let updatedUser = try await api.authorizedExecute {
      try authAPI.updateUser(user, redirectTo: redirectTo, pkce: pkce, accessToken: $0)
    }
    try await sessionStore.commit(.userUpdated(updatedUser, event: .userUpdated))
    return updatedUser
  }

  /// Gets all the identities linked to a user.
  public func userIdentities() async throws -> [UserIdentity] {
    try await user().identities ?? []
  }

  /// Link an identity to the current user using an ID token.
  @discardableResult
  public func linkIdentityWithIdToken(
    credentials: OpenIDConnectCredentials
  ) async throws -> Session {
    var credentials = credentials
    credentials.linkIdentity = true

    let session = try await api.execute(
      authAPI.signInWithIdToken(
        credentials: credentials, linkingTo: session.accessToken)
    )

    try await sessionStore.commit(.signedIn(session, event: .userUpdated))

    return session
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
  ) async throws {
    let response = try await linkIdentityURL(
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
  /// - Note: This method opens the URL with the platform's default handler. Where the platform
  /// cannot open a URL, such as Linux, it throws an error of kind
  /// ``AuthError/Kind-swift.struct/oauthFlowFailed``. To open the URL yourself, use
  /// ``linkIdentity(provider:scopes:redirectTo:queryParams:launchURL:)``.
  public func linkIdentity(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) async throws {
    let response = try await linkIdentityURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams
    )
    try await dependencies.platform.openURL(response.url)
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
  public func linkIdentityURL(
    provider: Provider,
    scopes: String? = nil,
    redirectTo: URL? = nil,
    queryParams: [(name: String, value: String?)] = []
  ) async throws -> OAuthResponse {
    let (pkce, flowId) = prepareForPKCE()
    let url = try await api.authorizedExecute {
      try authAPI.linkIdentityURL(
        provider: provider,
        scopes: scopes,
        redirectTo: redirectTo,
        queryParams: queryParams,
        pkce: pkce,
        accessToken: $0
      )
    }

    return OAuthResponse(provider: provider, url: url, flowId: flowId)
  }

  /// Unlinks an identity from a user by deleting it. The user will no longer be able to sign in
  /// with that identity once it's unlinked.
  public func unlinkIdentity(_ identity: UserIdentity) async throws {
    try await api.authorizedExecute { authAPI.unlinkIdentity(identity, accessToken: $0) }
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await api.execute(
      authAPI.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
        captchaToken: captchaToken,
        pkce: prepareForPKCE().challenge
      )
    )
  }

  /// Refresh and return a session, regardless of expiry status.
  /// - Parameter refreshToken: The optional refresh token to use for refreshing the session. If
  /// none is provided then this method refreshes the current session. When a concurrent refresh or
  /// sign-in replaced the current session during this call, and the new session is still valid,
  /// this method returns the new session without a request.
  /// - Returns: A new session, or the valid session that replaced the current one.
  /// - Throws: ``AuthError/sessionMissing`` when no `refreshToken` is given and there is no
  ///   current session.
  @discardableResult
  public func refreshSession(refreshToken: String? = nil) async throws -> Session {
    try await sessionManager.refreshSession(refreshToken)
  }

  /// Refreshes the session when less than half of its lifetime is left, and returns it.
  ///
  /// Call it from a `BGAppRefreshTask` handler, so the stored session is fresh when the app or
  /// one of its extensions next reads it. While enough lifetime is left, it returns the stored
  /// session without a request. It refreshes under every
  /// ``Configuration/autoRefresh`` policy.
  ///
  /// - Returns: The session, refreshed when needed, or `nil` when no user is signed in.
  @discardableResult
  public func refreshSessionIfNeeded() async throws -> Session? {
    try await sessionManager.refreshSessionIfNeeded()
  }

  /// Resumes auto refresh after ``stopAutoRefresh()``.
  ///
  /// The client refreshes the session 90 seconds before its access token expires. A failed
  /// refresh is retried with a capped exponential backoff. The expiry is judged from the local
  /// time the client received the session, so a wrong device clock does not change when the
  /// refresh runs. A session that is already due refreshes at once.
  ///
  /// With ``Configuration/autoRefresh`` set to ``AutoRefreshPolicy/automatic``, auto refresh
  /// starts when the client is created, so you call this only after ``stopAutoRefresh()``. Under
  /// the other policies it has no effect. Calls to this method and to ``stopAutoRefresh()`` take
  /// effect in the order you make them, and each returns once its call took effect.
  public func startAutoRefresh() async {
    await dependencies.autoRefresh.start()
  }

  /// Stops auto refresh until the next ``startAutoRefresh()``.
  ///
  /// A return to the foreground does not resume it.
  public func stopAutoRefresh() async {
    await dependencies.autoRefresh.stop()
  }

  /// Calls `deliver` with every change of the session store, in the order the store applied
  /// them, starting with ``AuthChangeEvent/initialSession`` once storage was read.
  ///
  /// The task holds no reference to the client.
  private static func observeAuthStateChanges(
    sessionStore: SessionStore,
    deliver: @escaping @Sendable (_ event: AuthChangeEvent, _ session: Session?) -> Void
  ) -> Task<Void, Never> {
    let changes = sessionStore.changes()
    return Task {
      try? await sessionStore.load()
      for await change in changes {
        deliver(change.event, change.status.session)
      }
    }
  }

  private static func postAuthStateChangeNotifications(
    sessionStore: SessionStore,
    logger: Logging.Logger
  ) -> Task<Void, Never> {
    let changes = sessionStore.changes()
    return Task {
      do {
        try await sessionStore.load()
      } catch {
        logger.error("Failed to load the stored session: \(error)")
      }
      for await change in changes {
        logger.trace("Auth state changed: \(change.event)")
        NotificationCenter.default.post(
          name: AuthClient.didChangeAuthStateNotification,
          object: nil,
          userInfo: [
            AuthClient.authChangeEventInfoKey: change.event,
            AuthClient.authChangeSessionInfoKey: change.status.session as Any,
          ]
        )
      }
    }
  }

  /// Starts a PKCE flow when the client uses one: stores a new code verifier under a new flow id
  /// and returns the challenge to send.
  private func prepareForPKCE() -> (challenge: PKCEChallenge?, flowId: String?) {
    guard configuration.flowType == .pkce else {
      return (nil, nil)
    }

    let flowId = UUID().uuidString
    let codeVerifier = pkce.generateCodeVerifier()
    codeVerifierStorage.set(codeVerifier, flowId)

    let codeChallenge = pkce.generateCodeChallenge(codeVerifier)
    let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

    return (
      PKCEChallenge(codeChallenge: codeChallenge, codeChallengeMethod: codeChallengeMethod),
      flowId
    )
  }

  private func isImplicitGrantFlow(params: [String: String]) -> Bool {
    params["access_token"] != nil || params["error_description"] != nil || params["error"] != nil
  }

  private func isPKCEFlow(params: [String: String]) -> Bool {
    let currentCodeVerifier = codeVerifierStorage.get(nil)
    return params["code"] != nil || params["error_description"] != nil || params["error"] != nil
      || params["error_code"] != nil && currentCodeVerifier != nil
  }

  /// Fetches a JWK from the JWKS endpoint with caching
  /// Returns nil if the key is not found, allowing graceful fallback to server-side verification
  private func fetchJWK(kid: String, jwks: JWKS? = nil) async throws -> JWK? {
    if let jwk = jwks?.keys.first(where: { $0.kid == kid }) {
      return jwk
    }

    let now = date()
    let storageKey = configuration.storageKey ?? defaultStorageKey

    if let cached = await globalJWKSCache.get(for: storageKey),
      let jwk = cached.jwks.keys.first(where: { $0.kid == kid })
    {
      if cached.cachedAt.addingTimeInterval(jwksTTL) > now {
        return jwk
      }
    }

    let fetchedJWKS = try await api.execute(authAPI.jwks())

    guard !fetchedJWKS.keys.isEmpty else {
      return nil
    }

    await globalJWKSCache.set(
      CachedJWKS(jwks: fetchedJWKS, cachedAt: now),
      for: storageKey
    )

    return fetchedJWKS.keys.first(where: { $0.kid == kid })
  }

  /// Extracts the JWT claims present in the access token by first verifying the
  /// JWT against the server's JSON Web Key Set endpoint `/.well-known/jwks.json`
  /// which is often cached, resulting in significantly faster responses. Prefer
  /// this method over ``user(jwt:)`` which always sends a request to the Auth
  /// server for each JWT.
  ///
  /// If the project is not using an asymmetric JWT signing key (like ECC or RSA)
  /// it always sends a request to the Auth server (similar to ``user(jwt:)``) to
  /// verify the JWT.
  ///
  /// - Parameters:
  ///   - jwt: An optional specific JWT you wish to verify, not the one you can obtain from ``session``.
  ///   - options: Various additional options that allow you to customize the behavior of this method.
  ///
  /// - Returns: A `JWTClaimsResponse` containing the verified claims, header, and signature.
  ///
  /// - Throws: ``AuthError`` with kind `.jwtVerificationFailed` if verification fails, or ``AuthError/sessionMissing`` if no session exists.
  public func claims(
    jwt: String? = nil,
    options: GetClaimsOptions = GetClaimsOptions()
  ) async throws -> JWTClaimsResponse {
    let token: String
    if let jwt {
      token = jwt
    } else {
      guard let session = try? await session else {
        throw AuthError.sessionMissing
      }
      token = session.accessToken
    }

    guard let decodedJWT = JWT.decode(token) else {
      throw AuthError.jwtVerificationFailed("Invalid JWT structure")
    }

    if !options.allowsExpired {
      if let exp = decodedJWT.payload["exp"] as? TimeInterval {
        let now = date().timeIntervalSince1970
        if exp <= now {
          throw AuthError.jwtVerificationFailed("JWT has expired")
        }
      }
    }

    let alg = decodedJWT.header["alg"] as? String
    let kid = decodedJWT.header["kid"] as? String

    let signingKey: JWK?
    if let alg, !alg.hasPrefix("HS"), let kid {
      signingKey = try await fetchJWK(kid: kid, jwks: options.jwks)
    } else {
      signingKey = nil
    }

    guard
      let signingKey,
      let algorithm = (signingKey.alg ?? alg).flatMap(JWTAlgorithm.init(rawValue:))
    else {
      _ = try await user(jwt: token)
      let claims = try configuration.resolvedDecoder.decode(
        JWTClaims.self,
        from: JSONSerialization.data(withJSONObject: decodedJWT.payload)
      )
      let header = try configuration.resolvedDecoder.decode(
        JWTHeader.self,
        from: JSONSerialization.data(withJSONObject: decodedJWT.header)
      )
      return JWTClaimsResponse(claims: claims, header: header, signature: decodedJWT.signature)
    }

    let isValid = algorithm.verify(jwt: decodedJWT, jwk: signingKey)

    guard isValid else {
      throw AuthError.jwtVerificationFailed("Invalid JWT signature")
    }

    let claims = try configuration.resolvedDecoder.decode(
      JWTClaims.self,
      from: JSONSerialization.data(withJSONObject: decodedJWT.payload)
    )
    let header = try configuration.resolvedDecoder.decode(
      JWTHeader.self,
      from: JSONSerialization.data(withJSONObject: decodedJWT.header)
    )

    return JWTClaimsResponse(claims: claims, header: header, signature: decodedJWT.signature)
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
