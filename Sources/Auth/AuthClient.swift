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
/// for await change in auth.events() {
///   print(change.event, change.session?.user.email ?? "signed out")
/// }
/// ```
///
/// ## Topics
///
/// ### Observing state
/// - ``events()``
/// - ``status``
/// - ``initialization()``
/// - ``currentSession``
/// - ``currentUser``
/// - ``session``
///
/// ### Signing up
/// - ``signUp(email:password:options:)``
/// - ``signUp(phone:password:options:)``
/// - ``SignUpResult``
/// - ``SignUpOptions``
/// - ``signInAnonymously(userMetadata:captchaToken:)``
///
/// ### Signing in
/// - ``signIn(email:password:captchaToken:)``
/// - ``signIn(phone:password:captchaToken:)``
/// - ``signInWithIDToken(_:)``
/// - ``IDTokenCredentials``
/// - ``Nonce``
/// - ``signInWithWeb3(_:)``
/// - ``signInWithOTP(email:redirectTo:shouldCreateUser:userMetadata:captchaToken:)``
/// - ``signInWithOTP(phone:channel:shouldCreateUser:userMetadata:captchaToken:)``
/// - ``signInWithSSO(domain:redirectTo:captchaToken:)``
/// - ``signInWithSSO(providerId:redirectTo:captchaToken:)``
/// - ``signInWithOAuth(_:options:presenter:)``
/// - ``oauthSignInURL(_:options:)``
/// - ``OAuthOptions``
/// - ``WebAuthPresenter``
/// - ``ClosurePresenter``
/// - ``ASWebAuthenticationSessionPresenter``
///
/// ### Handling redirects
/// - ``handleRedirect(_:)``
/// - ``isAuthRedirect(_:)``
/// - ``RedirectResult``
/// - ``exchangeCodeForSession(_:flowID:)``
///
/// ### Session management
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
/// - ``linkIdentity(_:options:presenter:)``
/// - ``linkIdentityWithIDToken(_:)``
/// - ``linkIdentityURL(_:options:)``
/// - ``unlinkIdentity(_:)``
///
/// ### JWT claims
/// - ``claims(jwt:options:)``
///
/// ### Namespaces
/// - ``mfa``
/// - ``admin``
/// - ``oauthServer``
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

  private var date: @Sendable () -> Date { dependencies.date }
  private var sessionManager: SessionManager { dependencies.sessionManager }
  private var sessionStore: SessionStore { dependencies.sessionStore }
  private var logger: Logging.Logger {
    dependencies.configuration.logger
  }

  private let lifecycleTask: Task<Void, Never>

  /// Returns the session, refreshing it if necessary.
  ///
  /// Throws an error of kind ``AuthError/Kind-swift.struct/sessionMissing`` when no session is
  /// stored, and of kind ``AuthError/Kind-swift.struct/sessionInvalidated`` when the server
  /// rejects the refresh of an expired session.
  ///
  /// When storage could not be read yet, each call reads it again, as do
  /// ``refreshSessionIfNeeded()``, requests that send the session's access token, each new
  /// ``events()`` stream, and ``initialization()``. While the device is locked it
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

  /// Whether a user is signed in, as the client knows it in memory.
  ///
  /// Reading it does no I/O. It is ``AuthStatus/loading`` until the client reads storage; use
  /// ``initialization()`` to wait for that.
  public var status: AuthStatus {
    sessionStore.currentStatus
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
  /// `beforeRefreshingHeldSession` runs after a call reads the held refresh token and before it
  /// asks the session store to refresh it, so a test can hold the call between the two.
  init(
    configuration: Configuration,
    date: @escaping @Sendable () -> Date,
    pkce: PKCE,
    platform: AuthPlatform,
    beforeRefreshingHeldSession: @escaping @Sendable () async -> Void = {}
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
      platform: platform,
      beforeRefreshingHeldSession: beforeRefreshingHeldSession
    )
    self.dependencies = dependencies
    Self.loadStoredSession(sessionStore: dependencies.sessionStore, logger: logger)

    let autoRefresh = dependencies.autoRefresh
    lifecycleTask = Self.observeAppLifecycle(
      platform: platform,
      sessionStore: dependencies.sessionStore,
      autoRefresh: configuration.observesAppLifecycle ? autoRefresh : nil
    )
    Task { await autoRefresh.apply() }
  }

  deinit {
    dependencies.sessionStore.finishChanges()
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

  /// Returns a stream of every change of the auth state, starting with the current one.
  ///
  /// The stream is registered when this method returns, so it loses no change, even one that
  /// happens before you start iterating. The first element is always
  /// ``AuthEvent/initialSession`` with the current ``status``, delivered once the client has read
  /// storage. Every later element is one change, in the order the client applied it. The session
  /// in the initial element may have expired since the last launch, so check
  /// ``Session/isExpired``.
  ///
  /// Each call returns a new stream for one consumer. The stream never throws: a failure that
  /// ends the session arrives as ``AuthEvent/signedOut`` with a ``AuthChange/signOutReason``. It
  /// finishes when the consuming task is cancelled or the client is released.
  ///
  /// ```swift
  /// for await change in auth.events() {
  ///   switch change.status {
  ///   case .signedIn(let session): showHome(for: session.user)
  ///   case .signedOut: showSignIn()
  ///   case .loading: break
  ///   }
  /// }
  /// ```
  public func events() -> AsyncStream<AuthChange> {
    let changes = sessionStore.changes()
    if status == .loading {
      Task { [sessionStore] in try? await sessionStore.load() }
    }
    return changes
  }

  /// Returns once the client has read storage, so ``status`` is no longer
  /// ``AuthStatus/loading``.
  ///
  /// While storage cannot be read, for example after a launch into the background before the
  /// first unlock, this waits until it can. It returns early when the calling task is cancelled.
  public func initialization() async {
    guard status == .loading else { return }
    let changes = sessionStore.changes()
    try? await sessionStore.load()
    for await _ in changes {
      return
    }
  }

  /// Creates a user with an email address and a password.
  ///
  /// When email confirmation is off, the user is signed in at once: the client stores the session
  /// and emits ``AuthEvent/signedIn``. When it is on, the server emails a confirmation link
  /// and the user stays signed out.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - password: The user's password.
  ///   - options: The user metadata, redirect URL, and captcha token. ``SignUpOptions/channel``
  ///     does not apply to email sign-up.
  /// - Returns: ``SignUpResult/signedIn(_:)`` with the new session, or
  ///   ``SignUpResult/confirmationRequired(_:)`` with the user to confirm.
  public func signUp(
    email: String,
    password: String,
    options: SignUpOptions = .init()
  ) async throws -> SignUpResult {
    try await withFlow(.signIn, redirectTo: options.redirectTo) { started in
      let result = try await _signUp(
        authAPI.signUp(
          email: email,
          password: password,
          userMetadata: options.userMetadata,
          redirectTo: options.redirectTo,
          captchaToken: options.captchaToken,
          pkce: started.challenge
        )
      )
      if result.session != nil {
        // No confirmation email was sent, so no code can come back for this flow.
        await removeFlow(started.flow.id)
      }
      return result
    }
  }

  /// Creates a user with a phone number and a password.
  ///
  /// When phone confirmation is off, the user is signed in at once: the client stores the session
  /// and emits ``AuthEvent/signedIn``. When it is on, the server sends a code over
  /// ``SignUpOptions/channel`` and the user stays signed out until
  /// ``verifyOTP(phone:token:type:captchaToken:)``.
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the international prefix.
  ///   - password: The user's password.
  ///   - options: The user metadata, channel, and captcha token. ``SignUpOptions/redirectTo``
  ///     does not apply to phone sign-up.
  /// - Returns: ``SignUpResult/signedIn(_:)`` with the new session, or
  ///   ``SignUpResult/confirmationRequired(_:)`` with the user to confirm.
  public func signUp(
    phone: String,
    password: String,
    options: SignUpOptions = .init()
  ) async throws -> SignUpResult {
    try await _signUp(
      authAPI.signUp(
        phone: phone,
        password: password,
        channel: options.channel,
        userMetadata: options.userMetadata,
        captchaToken: options.captchaToken
      )
    )
  }

  private func _signUp(_ request: AuthRequest<SignUpResult>) async throws -> SignUpResult {
    let result = try await api.execute(request)

    if case .signedIn(let session) = result {
      try await sessionStore.commit(.signedIn(session, event: .signedIn))
    }

    return result
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
  ///   - phone: User's phone number.
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

  /// Signs in with an ID token that a third-party identity provider issued, such as Sign in with
  /// Apple or Google Sign-In.
  ///
  /// The server checks the token and creates the user if needed.
  ///
  /// ```swift
  /// let nonce = Nonce.generate()
  /// request.nonce = nonce.hashed  // Pass the hashed nonce to the provider.
  /// // ...
  /// try await client.auth.signInWithIDToken(
  ///   IDTokenCredentials(provider: .apple, idToken: idToken, nonce: nonce.raw)
  /// )
  /// ```
  ///
  /// - Parameter credentials: The ID token and the values the server needs to check it.
  /// - Returns: The new session.
  @discardableResult
  public func signInWithIDToken(_ credentials: IDTokenCredentials) async throws -> Session {
    try await _signIn(authAPI.signInWithIDToken(credentials: credentials))
  }

  /// Signs in a user via a signed Sign in with Ethereum (EIP-4361) or Sign in with Solana message.
  ///
  /// The app is responsible for building the message and obtaining the signature from the user's
  /// wallet (e.g. via a WalletConnect session or native wallet SDK) before calling this method.
  ///
  /// ```swift
  /// let session = try await client.auth.signInWithWeb3(
  ///   Web3Credentials(
  ///     chain: .ethereum,
  ///     message: siweMessage,
  ///     signature: signatureHex
  ///   )
  /// )
  /// ```
  @discardableResult
  public func signInWithWeb3(_ credentials: Web3Credentials) async throws -> Session {
    try await _signIn(authAPI.signInWithWeb3(credentials: credentials))
  }

  /// Creates a new anonymous user.
  /// - Parameters:
  ///   - userMetadata: Data to store on the user, in the `auth.users.raw_user_meta_data` column.
  ///   - captchaToken: The token the user received for completing a captcha.
  @discardableResult
  public func signInAnonymously(
    userMetadata: JSONObject = [:],
    captchaToken: String? = nil
  ) async throws -> Session {
    try await _signIn(
      authAPI.signInAnonymously(userMetadata: userMetadata, captchaToken: captchaToken))
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
  ///   - userMetadata: Data to store on the user if the call creates one.
  ///   - captchaToken: Captcha verification token.
  public func signInWithOTP(
    email: String,
    redirectTo: URL? = nil,
    shouldCreateUser: Bool = true,
    userMetadata: JSONObject = [:],
    captchaToken: String? = nil
  ) async throws {
    try await withFlow(.signIn, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.signInWithOTP(
          email: email,
          redirectTo: redirectTo,
          shouldCreateUser: shouldCreateUser,
          userMetadata: userMetadata,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
    }
  }

  /// Log in user using a one-time password (OTP)..
  ///
  /// - Parameters:
  ///   - phone: User's phone with international prefix.
  ///   - channel: Messaging channel to use (e.g `whatsapp` or `sms`), defaults to `sms`.
  ///   - shouldCreateUser: Creates a new user, defaults to `true`.
  ///   - userMetadata: Data to store on the user if the call creates one.
  ///   - captchaToken: Captcha verification token.
  ///
  /// - Note: You need to configure a WhatsApp sender on Twilio if you are using phone sign in with the `whatsapp` channel.
  public func signInWithOTP(
    phone: String,
    channel: MessagingChannel = .sms,
    shouldCreateUser: Bool = true,
    userMetadata: JSONObject = [:],
    captchaToken: String? = nil
  ) async throws {
    try await api.execute(
      authAPI.signInWithOTP(
        phone: phone,
        channel: channel,
        shouldCreateUser: shouldCreateUser,
        userMetadata: userMetadata,
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
    try await withFlow(.signIn, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.signInWithSSO(
          domain: domain,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
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
  ) async throws -> SSOResponse {
    try await withFlow(.signIn, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.signInWithSSO(
          providerId: providerId,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
    }
  }

  /// Returns the URL that starts an OAuth sign-in with a third-party provider.
  ///
  /// Use it when you present the provider page yourself. The client stores a new PKCE flow before
  /// it returns. Pass the redirect URL that comes back to ``handleRedirect(_:)``, or pass the code
  /// and `flowID` to ``exchangeCodeForSession(_:flowID:)``.
  ///
  /// - Parameters:
  ///   - provider: The third-party provider.
  ///   - options: The scopes, the redirect URL, and extra query items.
  /// - Returns: The URL to open, and the ID of the flow that this call started.
  public func oauthSignInURL(
    _ provider: Provider,
    options: OAuthOptions = .init()
  ) async throws -> (url: URL, flowID: UUID) {
    let redirectTo = Self.oauthRedirectURL(
      redirectTo: options.redirectTo, configured: configuration.redirectToURL)
    return try await withFlow(.signIn, redirectTo: redirectTo) { started in
      let url = try authAPI.authorizeURL(
        provider: provider,
        scopes: options.scopesParameter,
        redirectTo: redirectTo,
        queryParams: options.queryParams,
        pkce: started.challenge
      )
      return (url, started.flow.id)
    }
  }

  #if canImport(AuthenticationServices)
    /// Signs in with a third-party provider, and stores the session.
    ///
    /// The client starts a PKCE flow, shows the provider page with `presenter`, and exchanges the
    /// code from the callback URL. It emits ``AuthEvent/signedIn``.
    ///
    /// ```swift
    /// try await supabase.auth.signInWithOAuth(
    ///   .github,
    ///   options: OAuthOptions(redirectTo: URL(string: "myapp://login-callback"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - provider: The third-party provider.
    ///   - options: The scopes, the redirect URL, and extra query items.
    ///   - presenter: Shows the provider page. The default is
    ///     ``ASWebAuthenticationSessionPresenter``.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. Else the error of `presenter`, or an
    ///   error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is
    ///   not an auth redirect or reports an error. The client removes the flow when `presenter`
    ///   throws.
    @discardableResult
    public func signInWithOAuth(
      _ provider: Provider,
      options: OAuthOptions = .init(),
      presenter: some WebAuthPresenter = .default
    ) async throws -> Session {
      try await present(
        oauthSignInURL(provider, options: options), options: options, with: presenter)
    }
  #else
    /// Signs in with a third-party provider, and stores the session.
    ///
    /// The client starts a PKCE flow, shows the provider page with `presenter`, and exchanges the
    /// code from the callback URL. It emits ``AuthEvent/signedIn``.
    ///
    /// - Parameters:
    ///   - provider: The third-party provider.
    ///   - options: The scopes, the redirect URL, and extra query items.
    ///   - presenter: Shows the provider page.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. Else the error of `presenter`, or an
    ///   error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is
    ///   not an auth redirect or reports an error. The client removes the flow when `presenter`
    ///   throws.
    @discardableResult
    public func signInWithOAuth(
      _ provider: Provider,
      options: OAuthOptions = .init(),
      presenter: some WebAuthPresenter
    ) async throws -> Session {
      try await present(
        oauthSignInURL(provider, options: options), options: options, with: presenter)
    }
  #endif

  /// Shows `start.url` with `presenter`, then finishes the flow with the callback URL.
  private func present(
    _ start: (url: URL, flowID: UUID),
    options: OAuthOptions,
    with presenter: some WebAuthPresenter
  ) async throws -> Session {
    // A sign-out while the page is open must win over the callback.
    let signOuts = await sessionStore.signOuts
    let callbackScheme = Self.oauthRedirectURL(
      redirectTo: options.redirectTo, configured: configuration.redirectToURL)?.scheme

    let callback: URL
    do {
      callback = try await presenter.authenticate(url: start.url, callbackScheme: callbackScheme)
    } catch {
      await removeFlow(start.flowID)
      throw error
    }

    // The page is closed, so no other code can come back for this flow. Only an exchange that may
    // not have reached the server keeps it, so a retry can still finish it.
    let result: RedirectResult?
    do {
      result = try await handleRedirect(callback, flowID: start.flowID, signOuts: signOuts)
    } catch {
      if !Self.mayHaveReachedServer(error) {
        await removeFlow(start.flowID)
      }
      throw error
    }

    // A code exchange removed the flow already. Implicit tokens or a non-redirect leave it.
    await removeFlow(start.flowID)
    switch result {
    case .signedIn(let session, _):
      return session
    case .emailChangePending:
      throw AuthError.oauthFlowFailed(
        "The callback URL reports a pending email change, not a session.")
    case nil:
      throw AuthError.oauthFlowFailed("The callback URL is not an auth redirect.")
    }
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

  /// Exchanges an authorization code for a session, and stores the session.
  ///
  /// The client emits one auth event, chosen by the call that started the flow:
  /// ``AuthEvent/passwordRecovery`` for ``resetPasswordForEmail(_:redirectTo:captchaToken:)``,
  /// ``AuthEvent/userUpdated`` for an email change or an identity link, and
  /// ``AuthEvent/signedIn`` otherwise.
  ///
  /// This call is not deduplicated. To handle a redirect URL that can arrive more than once, use
  /// ``handleRedirect(_:)``.
  ///
  /// - Parameters:
  ///   - code: The authorization code from the redirect URL.
  ///   - flowID: The ID of the flow that produced `code`, as returned by
  ///     ``oauthSignInURL(_:options:)`` or ``linkIdentityURL(_:options:)``. When `nil`, the client
  ///     tries the pending flows newest first.
  /// - Returns: The new session.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when no pending
  ///   flow matches, without a request.
  public func exchangeCodeForSession(_ code: String, flowID: UUID? = nil) async throws -> Session {
    try await exchange(code: code, flowID: flowID, signOuts: sessionStore.signOuts).session
  }

  /// Returns `true` when `url` is a redirect that ``handleRedirect(_:)`` handles.
  ///
  /// It reads only the URL, not storage. A URL with a code returns `true` even when no flow
  /// waits for it.
  public func isAuthRedirect(_ url: URL) -> Bool {
    AuthRedirect.parse(url) != nil
  }

  /// Finishes the auth flow that a redirect URL reports, and stores the session.
  ///
  /// Pass the URLs that reach your auth callback. ``isAuthRedirect(_:)`` checks one. The client
  /// reads the URL's contents to find the flow: a PKCE code, tokens from an email link, an error,
  /// or an email change that waits for a second confirmation.
  ///
  /// A code without a flow ID, such as the code in an email link, can belong to any pending flow.
  /// The client tries the pending flows newest first, so a link from an earlier email can still
  /// finish its own flow. The server may have made that link invalid already, for example when a
  /// later email went to the same user.
  ///
  /// A URL with tokens (`#access_token=…`) signs in the account that the tokens belong to, with
  /// no pending flow. Anyone who can make your app open a URL can sign it in to their own account
  /// this way. Pass only URLs that reach your own callback.
  ///
  /// The same URL can arrive more than once, for example from both a scene delegate and
  /// `onOpenURL`. A redelivery returns the same result, or throws the same error, and sends no
  /// request. That includes a transport error: to retry the exchange after one, call
  /// ``exchangeCodeForSession(_:flowID:)`` with the code. The flow stays stored after a transport
  /// error, so the retry can still succeed.
  ///
  /// ```swift
  /// SomeView()
  ///   .onOpenURL { url in
  ///     Task { try await supabase.auth.handleRedirect(url) }
  ///   }
  /// ```
  ///
  /// - Parameter url: The URL that opened the app.
  /// - Returns: `nil` when `url` is not an auth redirect, else what the redirect did.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the URL
  ///   reports an error or no pending flow matches its code, or the error of the request.
  ///   `CancellationError` when ``signOut(scope:)`` finished while the redirect was handled; the
  ///   client then stores nothing.
  @discardableResult
  public func handleRedirect(_ url: URL) async throws -> RedirectResult? {
    try await handleRedirect(url, flowID: nil)
  }

  /// `flowID` names the flow the caller started. It wins over the URL's `sb_flow_id`.
  ///
  /// `signOuts` is the sign-out count when the sign-in started; a later sign-out discards it.
  /// `nil` reads the count now.
  func handleRedirect(
    _ url: URL,
    flowID: UUID?,
    signOuts: UInt64? = nil
  ) async throws -> RedirectResult? {
    guard let redirect = AuthRedirect.parse(url) else { return nil }
    let started = if let signOuts { signOuts } else { await sessionStore.signOuts }

    switch redirect {
    case .error(let error):
      throw error

    case .emailChangePending(let message):
      return .emailChangePending(message: message)

    case .code(let code, let urlFlowID):
      return try await dependencies.redirectDeduplicator.value(for: code) { [self] in
        let (session, flow) = try await exchange(
          code: code, flowID: flowID ?? urlFlowID, signOuts: started)
        return .signedIn(session, verification: flow.purpose.verification)
      }

    case .implicit(let tokens, let type):
      return try await dependencies.redirectDeduplicator.value(for: tokens.accessToken) { [self] in
        let session = try await signIn(with: tokens, type: type, signOuts: started)
        return .signedIn(session, verification: type)
      }
    }
  }

  /// Exchanges `code` with the flow `flowID` names. With an ID, never falls back to another flow.
  ///
  /// Without an ID, the code can belong to any pending flow, for example an email link that cannot
  /// carry an ID. The client tries the flows newest first. A ``ErrorCode/badCodeVerifier``
  /// rejection means the code belongs to another flow, so the client tries the next one. Any other
  /// rejection throws. A guessed flow is kept on every rejection, because a rejection does not
  /// prove the code was that flow's; the TTL drops it.
  private func exchange(
    code: String,
    flowID: UUID?,
    signOuts: UInt64
  ) async throws -> (session: Session, flow: PendingFlowRecord) {
    if let flowID {
      guard let flow = try await dependencies.flowStore.flow(id: flowID) else {
        throw AuthError.oauthFlowFailed(
          "No pending flow with ID \(flowID). It finished, expired, or started on another device.")
      }
      return (try await exchange(code: code, flow: flow, guessed: false, signOuts: signOuts), flow)
    }

    let flows = try await dependencies.flowStore.pendingFlows()
    var rejection: (any Error)?
    for flow in flows {
      do {
        return (
          try await exchange(code: code, flow: flow, guessed: true, signOuts: signOuts), flow
        )
      } catch let error as AuthError where error.errorCode == .badCodeVerifier {
        rejection = error
      }
    }
    throw rejection
      ?? AuthError.oauthFlowFailed(
        "No pending flow for this code. It finished, expired, or started on another device.")
  }

  /// `guessed` is `true` when the caller chose `flow` without an ID. A rejection then keeps `flow`,
  /// because it does not prove the code belongs to `flow`.
  private func exchange(
    code: String,
    flow: PendingFlowRecord,
    guessed: Bool,
    signOuts: UInt64
  ) async throws -> Session {
    let session: Session
    do {
      session = try await api.execute(
        authAPI.exchangeCodeForSession(authCode: code, codeVerifier: flow.verifier))
    } catch {
      // After a transport error the server may not have seen the code, so a retry can still work.
      if !guessed, let error = error as? AuthError, error.response != nil {
        await removeFlow(flow.id)
      }
      throw error
    }

    await removeFlow(flow.id)
    try await sessionStore.commit(flow.purpose.transition(session), unlessSignedOutSince: signOuts)
    return session
  }

  /// A failed removal is only logged. The flow cannot be used again, and the TTL drops it.
  private func removeFlow(_ id: UUID) async {
    do {
      try await dependencies.flowStore.remove(id: id)
    } catch {
      logger.error("Failure removing a finished flow: \(error.localizedDescription)")
    }
  }

  private func signIn(
    with tokens: ImplicitTokens,
    type: EmailOTPType?,
    signOuts: UInt64
  ) async throws -> Session {
    let user = try await api.execute(
      authAPI.user(accessToken: tokens.accessToken, tokenType: tokens.tokenType),
      for: sessionOwnership(ofAccessToken: tokens.accessToken)
    )

    let session = Session(
      providerToken: tokens.providerToken,
      providerRefreshToken: tokens.providerRefreshToken,
      accessToken: tokens.accessToken,
      tokenType: tokens.tokenType,
      expiresIn: tokens.expiresIn,
      expiresAt: tokens.expiresAt
        ?? date().addingTimeInterval(tokens.expiresIn).timeIntervalSince1970,
      refreshToken: tokens.refreshToken,
      user: user
    )

    try await sessionStore.commit(
      Self.verifiedTransition(session, for: type),
      unlessSignedOutSince: signOuts
    )
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
  /// If using ``SignOutScope/others`` scope, no ``AuthEvent/signedOut`` event is fired.
  /// - Parameter scope: Specifies which sessions should be logged out.
  public func signOut(scope: SignOutScope = .global) async throws {
    if scope != .others {
      // A redirect handled before the sign-out must sign in again when it comes back.
      await dependencies.redirectDeduplicator.removeAll()
    }

    guard let session = currentSession else {
      configuration.logger.warning("signOut called without a session")
      if scope != .others {
        // A sign-in that started before this call must not commit after it.
        try await sessionStore.recordSignOut()
      }
      return
    }

    if scope != .others {
      try await sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
      // A redirect cached between the first clear and the commit must not replay either.
      await dependencies.redirectDeduplicator.removeAll()
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
      ),
      transition: { Self.verifiedTransition($0, for: type) }
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
      authAPI.verifyOTP(phone: phone, token: token, type: type, captchaToken: captchaToken),
      transition: {
        type == .phoneChange ? .userChangeVerified($0) : .signedIn($0, event: .signedIn)
      }
    )
  }

  /// Log in an user given a token hash received via email.
  @discardableResult
  public func verifyOTP(
    tokenHash: String,
    type: EmailOTPType
  ) async throws -> VerifyOTPResponse {
    try await _verifyOTP(
      authAPI.verifyOTP(tokenHash: tokenHash, type: type),
      transition: { Self.verifiedTransition($0, for: type) }
    )
  }

  private static func verifiedTransition(
    _ session: Session,
    for type: EmailOTPType?
  ) -> SessionStore.Transition {
    switch type {
    case .recovery: .signedIn(session, event: .passwordRecovery)
    case .emailChange: .userChangeVerified(session)
    default: .signedIn(session, event: .signedIn)
    }
  }

  private func _verifyOTP(
    _ request: AuthRequest<VerifyOTPResponse>,
    transition: (Session) -> SessionStore.Transition
  ) async throws -> VerifyOTPResponse {
    let response = try await api.execute(request)

    if let session = response.session {
      try await sessionStore.commit(transition(session))
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
    try await withFlow(type == .emailChange ? .emailChange : .signIn, redirectTo: emailRedirectTo) {
      try await api.execute(
        authAPI.resend(
          email: email,
          type: type,
          redirectTo: emailRedirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
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
    guard user.email != nil else {
      return try await updateUser(user, redirectTo: redirectTo, pkce: nil)
    }
    return try await withFlow(.emailChange, redirectTo: redirectTo) {
      try await updateUser(user, redirectTo: redirectTo, pkce: $0.challenge)
    }
  }

  private func updateUser(
    _ user: UserAttributes,
    redirectTo: URL?,
    pkce: PKCEChallenge?
  ) async throws -> User {
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

  /// Links an identity to the current user with an ID token that a third-party identity provider
  /// issued.
  ///
  /// - Parameter credentials: The ID token and the values the server needs to check it.
  /// - Returns: The updated session.
  @discardableResult
  public func linkIdentityWithIDToken(_ credentials: IDTokenCredentials) async throws -> Session {
    let session = try await api.execute(
      authAPI.signInWithIDToken(credentials: credentials, linkingTo: session.accessToken)
    )

    try await sessionStore.commit(.signedIn(session, event: .userUpdated))

    return session
  }

  /// Returns the URL that links an OAuth identity to the signed-in user.
  ///
  /// Use it when you present the provider page yourself. The client stores a new PKCE flow before
  /// it returns. Pass the redirect URL that comes back to ``handleRedirect(_:)``, which emits
  /// ``AuthEvent/userUpdated``.
  ///
  /// - Parameters:
  ///   - provider: The provider to link.
  ///   - options: The scopes, the redirect URL, and extra query items.
  /// - Returns: The URL to open, and the ID of the flow that this call started.
  public func linkIdentityURL(
    _ provider: Provider,
    options: OAuthOptions = .init()
  ) async throws -> (url: URL, flowID: UUID) {
    let redirectTo = Self.oauthRedirectURL(
      redirectTo: options.redirectTo, configured: configuration.redirectToURL)
    return try await withFlow(.linkIdentity, redirectTo: redirectTo) { started in
      let url = try await api.authorizedExecute {
        try authAPI.linkIdentityURL(
          provider: provider,
          scopes: options.scopesParameter,
          redirectTo: redirectTo,
          queryParams: options.queryParams,
          pkce: started.challenge,
          accessToken: $0
        )
      }
      return (url, started.flow.id)
    }
  }

  #if canImport(AuthenticationServices)
    /// Links an OAuth identity to the signed-in user.
    ///
    /// The client starts a PKCE flow, shows the provider page with `presenter`, and exchanges the
    /// code from the callback URL. It emits ``AuthEvent/userUpdated``.
    ///
    /// - Parameters:
    ///   - provider: The provider to link.
    ///   - options: The scopes, the redirect URL, and extra query items.
    ///   - presenter: Shows the provider page. The default is
    ///     ``ASWebAuthenticationSessionPresenter``.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. ``AuthError/sessionMissing`` when no
    ///   user is signed in. Else the error of `presenter`, or an error of kind
    ///   ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is not an auth
    ///   redirect or reports an error. The client removes the flow when `presenter` throws.
    @discardableResult
    public func linkIdentity(
      _ provider: Provider,
      options: OAuthOptions = .init(),
      presenter: some WebAuthPresenter = .default
    ) async throws -> Session {
      try await present(
        linkIdentityURL(provider, options: options), options: options, with: presenter)
    }
  #else
    /// Links an OAuth identity to the signed-in user.
    ///
    /// The client starts a PKCE flow, shows the provider page with `presenter`, and exchanges the
    /// code from the callback URL. It emits ``AuthEvent/userUpdated``.
    ///
    /// - Parameters:
    ///   - provider: The provider to link.
    ///   - options: The scopes, the redirect URL, and extra query items.
    ///   - presenter: Shows the provider page.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. ``AuthError/sessionMissing`` when no
    ///   user is signed in. Else the error of `presenter`, or an error of kind
    ///   ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is not an auth
    ///   redirect or reports an error. The client removes the flow when `presenter` throws.
    @discardableResult
    public func linkIdentity(
      _ provider: Provider,
      options: OAuthOptions = .init(),
      presenter: some WebAuthPresenter
    ) async throws -> Session {
      try await present(
        linkIdentityURL(provider, options: options), options: options, with: presenter)
    }
  #endif

  /// Unlinks an identity from a user by deleting it. The user will no longer be able to sign in
  /// with that identity once it's unlinked.
  ///
  /// When the identity belongs to the signed-in user, the client removes it from
  /// ``currentUser`` and emits ``AuthEvent/userUpdated``.
  public func unlinkIdentity(_ identity: UserIdentity) async throws {
    try await api.authorizedExecute { authAPI.unlinkIdentity(identity, accessToken: $0) }
    // The response carries no user, so the store drops the identity from the held one.
    try await sessionStore.commit(
      .identityUnlinked(identity.identityId, userID: identity.userId))
  }

  /// Sends a reset request to an email address.
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await withFlow(.recovery, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.resetPasswordForEmail(
          email,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
    }
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

  private static func loadStoredSession(sessionStore: SessionStore, logger: Logging.Logger) {
    Task {
      do {
        try await sessionStore.load()
      } catch {
        logger.error("Failed to load the stored session: \(error)")
      }
    }
  }

  /// Stores a new PKCE flow, then runs `request`, which starts the flow on the server.
  ///
  /// When `request` fails, the flow is removed, so it cannot become the newest flow that a later
  /// code without a flow ID is exchanged with. A transport error or a cancellation keeps it: the
  /// request may have reached the server, and its email may already be out. A decoding error keeps
  /// it too: it follows a 2xx, so the server accepted the request.
  private func withFlow<Result>(
    _ purpose: PendingFlowRecord.Purpose,
    redirectTo: URL?,
    _ request: (_ started: (flow: PendingFlowRecord, challenge: PKCEChallenge)) async throws ->
      Result
  ) async throws -> Result {
    let started = try await dependencies.flowStore.start(
      purpose: purpose,
      redirectTo: redirectTo ?? configuration.redirectToURL
    )
    do {
      return try await request(started)
    } catch {
      if !Self.mayHaveReachedServer(error) {
        await removeFlow(started.flow.id)
      }
      throw error
    }
  }

  private static func mayHaveReachedServer(_ error: any Error) -> Bool {
    if error is CancellationError || error is URLError { return true }
    guard let error = error as? AuthError else { return false }
    return error.kind == .transport || error.kind == .decoding
      || error.underlyingError is URLError
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
