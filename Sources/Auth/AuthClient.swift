import ConcurrencyExtras
public import Foundation
import IssueReporting
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

typealias AuthClientID = Int

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
/// - ``signInWithOAuth(_:options:presenter:)``
/// - ``oauthSignInURL(_:options:)``
/// - ``OAuthOptions``
/// - ``OAuthFlow``
/// - ``WebAuthPresenter``
/// - ``ClosurePresenter``
/// - ``ASWebAuthenticationSessionPresenter``
///
/// ### One-time passwords and magic links
/// - ``signInWithOTP(email:options:)``
/// - ``signInWithOTP(phone:options:)``
/// - ``EmailOTPOptions``
/// - ``PhoneOTPOptions``
/// - ``MessagingChannel``
/// - ``MessageID``
/// - ``verifyOTP(email:token:type:)``
/// - ``verifyOTP(phone:token:type:)``
/// - ``verifyOTP(tokenHash:type:)``
/// - ``EmailOTPType``
/// - ``PhoneOTPType``
/// - ``VerifyOTPResult``
/// - ``resend(email:type:redirectTo:captchaToken:)``
/// - ``resend(phone:type:captchaToken:)``
/// - ``ResendEmailType``
/// - ``ResendPhoneType``
///
/// ### Single sign-on
/// - ``signInWithSSO(_:options:presenter:)``
/// - ``ssoSignInURL(_:options:)``
/// - ``SSOTarget``
/// - ``SSOOptions``
///
/// ### Handling redirects
/// - ``handleRedirect(_:)``
/// - ``isAuthRedirect(_:)``
/// - ``RedirectResult``
/// - ``exchangeCodeForSession(_:flowID:)``
///
/// ### Session management
/// - ``session()``
/// - ``importSession(accessToken:refreshToken:)``
/// - ``refreshSession()``
/// - ``refreshSessionIfNeeded()``
/// - ``startAutoRefresh()``
/// - ``stopAutoRefresh()``
///
/// ### Signing out
/// - ``signOut(scope:)``
///
/// ### User management
/// - ``user()``
/// - ``user(jwt:)``
/// - ``updateUser(_:redirectTo:)``
/// - ``UserAttributes``
/// - ``reauthenticate()``
/// - ``resetPassword(email:redirectTo:captchaToken:)``
///
/// ### Identities
/// - ``identities()``
/// - ``linkIdentity(_:options:presenter:)``
/// - ``linkIdentity(idToken:)``
/// - ``linkIdentityURL(_:options:)``
/// - ``unlinkIdentity(_:)``
///
/// ### JWT claims
/// - ``claims(options:)``
/// - ``claims(jwt:options:)``
///
/// ### Namespaces
/// - ``mfa``
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

  private let jwksCache: JWKSCache

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

  /// Returns the session, refreshing it first when its access token expires in less than 30
  /// seconds.
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
  public func session() async throws -> Session {
    try await sessionManager.session()
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
  /// Reading it does no I/O, so the session may be expired. Use ``session()`` for
  /// a session that is valid.
  public var currentSession: Session? {
    sessionStore.currentSession
  }

  /// Returns the current user, if any.
  ///
  /// The user returned by this property may be outdated. Use ``user()`` to fetch an up-to-date user.
  public var currentUser: User? {
    currentSession?.user
  }

  /// Namespace for accessing multi-factor authentication API.
  public let mfa: AuthMFA

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
    self.mfa = AuthMFA(dependencies: dependencies)
    jwksCache = JWKSCache(
      fetch: { [api = dependencies.sessionAPI, authAPI = dependencies.authAPI] in
        try await api.execute(authAPI.jwks())
      },
      now: date
    )
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
  /// storage. When the stored session is expired and ``Configuration/autoRefresh`` is
  /// ``AutoRefreshPolicy/automatic``, the client first tries one refresh, for at most
  /// ``Configuration/initialRefreshTimeout``. The initial element then carries the refreshed
  /// session, or ``AuthStatus/signedOut(_:)`` when the server rejected the refresh token. Every
  /// later element is one change, in the order the client applied it. When the refresh fails for
  /// another reason, such as no network, the session in the initial element is still expired, so
  /// check ``Session/isExpired``. A refresh that outlasts the timeout still commits later, as
  /// ``AuthEvent/tokenRefreshed``, or as ``AuthEvent/signedOut`` when the server rejects the
  /// refresh token.
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
  /// ``AuthStatus/loading``. When it refreshes an expired stored session first, this waits for
  /// that refresh too, for at most ``Configuration/initialRefreshTimeout``.
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
  /// ``verifyOTP(phone:token:type:)``.
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

  /// Sends a one-time code or a magic link to an email address.
  ///
  /// The email template decides what the user gets: `{{ .ConfirmationURL }}` sends a magic link,
  /// and `{{ .Token }}` sends a code. Pass the code to
  /// ``verifyOTP(email:token:type:)``, or the redirect URL of the link to
  /// ``handleRedirect(_:)``. The client stores a PKCE flow for the link before the request.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - options: Whether to create the user, its metadata, the redirect URL of the link, and the
  ///     captcha token.
  public func signInWithOTP(email: String, options: EmailOTPOptions = .init()) async throws {
    try await withFlow(.signIn, redirectTo: options.redirectTo) {
      try await api.execute(
        authAPI.signInWithOTP(email: email, options: options, pkce: $0.challenge))
    }
  }

  /// Sends a one-time code to a phone number by SMS or WhatsApp.
  ///
  /// Pass the code to ``verifyOTP(phone:token:type:)`` with
  /// ``PhoneOTPType/sms``.
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the international prefix.
  ///   - options: Whether to create the user, its metadata, the channel, and the captcha token.
  /// - Returns: The ID that the SMS provider gave the message, or `nil` when the provider sent
  ///   none.
  @discardableResult
  public func signInWithOTP(
    phone: String,
    options: PhoneOTPOptions = .init()
  ) async throws -> MessageID? {
    try await api.execute(authAPI.signInWithOTP(phone: phone, options: options))
  }

  /// Returns the URL that starts a SAML single sign-on with an identity provider.
  ///
  /// Use it when you present the identity provider page yourself. The client stores a new PKCE
  /// flow before it returns. Pass the redirect URL that comes back to ``handleRedirect(_:)``, or
  /// pass the code and ``OAuthFlow/id`` to ``exchangeCodeForSession(_:flowID:)``.
  ///
  /// - Parameters:
  ///   - target: The email domain or the ID of the identity provider.
  ///   - options: The redirect URL and the captcha token.
  /// - Returns: The flow that this call started, with the URL to open.
  public func ssoSignInURL(
    _ target: SSOTarget,
    options: SSOOptions = .init()
  ) async throws -> OAuthFlow {
    let redirectTo = Self.oauthRedirectURL(
      redirectTo: options.redirectTo, configured: configuration.redirectToURL)
    return try await withFlow(.signIn, redirectTo: redirectTo, sendsEmail: false) { started in
      let url = try await api.execute(
        authAPI.signInWithSSO(
          target,
          redirectTo: redirectTo,
          captchaToken: options.captchaToken,
          pkce: started.challenge
        )
      )
      return OAuthFlow(id: started.flow.id, url: url)
    }
  }

  #if canImport(AuthenticationServices)
    /// Signs in with SAML single sign-on, and stores the session.
    ///
    /// The client starts a PKCE flow, shows the identity provider page with `presenter`, and
    /// exchanges the code from the callback URL. It emits ``AuthEvent/signedIn``.
    ///
    /// ```swift
    /// try await supabase.auth.signInWithSSO(
    ///   .domain("example.com"),
    ///   options: SSOOptions(redirectTo: URL(string: "myapp://login-callback"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - target: The email domain or the ID of the identity provider.
    ///   - options: The redirect URL and the captcha token.
    ///   - presenter: Shows the identity provider page. The default is
    ///     ``ASWebAuthenticationSessionPresenter``.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. Else the error of `presenter`, or an
    ///   error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is
    ///   not an auth redirect or reports an error. The client removes the flow when `presenter`
    ///   throws.
    @discardableResult
    public func signInWithSSO(
      _ target: SSOTarget,
      options: SSOOptions = .init(),
      presenter: some WebAuthPresenter = .default
    ) async throws -> Session {
      try await present(
        ssoSignInURL(target, options: options), redirectTo: options.redirectTo, with: presenter)
    }
  #else
    /// Signs in with SAML single sign-on, and stores the session.
    ///
    /// The client starts a PKCE flow, shows the identity provider page with `presenter`, and
    /// exchanges the code from the callback URL. It emits ``AuthEvent/signedIn``.
    ///
    /// - Parameters:
    ///   - target: The email domain or the ID of the identity provider.
    ///   - options: The redirect URL and the captcha token.
    ///   - presenter: Shows the identity provider page.
    /// - Returns: The new session.
    /// - Throws: `CancellationError` when the user cancels. Else the error of `presenter`, or an
    ///   error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when the callback URL is
    ///   not an auth redirect or reports an error. The client removes the flow when `presenter`
    ///   throws.
    @discardableResult
    public func signInWithSSO(
      _ target: SSOTarget,
      options: SSOOptions = .init(),
      presenter: some WebAuthPresenter
    ) async throws -> Session {
      try await present(
        ssoSignInURL(target, options: options), redirectTo: options.redirectTo, with: presenter)
    }
  #endif

  /// Returns the URL that starts an OAuth sign-in with a third-party provider.
  ///
  /// Use it when you present the provider page yourself. The client stores a new PKCE flow before
  /// it returns. Pass the redirect URL that comes back to ``handleRedirect(_:)``, or pass the code
  /// and ``OAuthFlow/id`` to ``exchangeCodeForSession(_:flowID:)``.
  ///
  /// - Parameters:
  ///   - provider: The third-party provider.
  ///   - options: The scopes, the redirect URL, and extra query items.
  /// - Returns: The flow that this call started: the URL to open, and the flow ID.
  public func oauthSignInURL(
    _ provider: Provider,
    options: OAuthOptions = .init()
  ) async throws -> OAuthFlow {
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
      return OAuthFlow(id: started.flow.id, url: url)
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
        oauthSignInURL(provider, options: options), redirectTo: options.redirectTo, with: presenter)
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
        oauthSignInURL(provider, options: options), redirectTo: options.redirectTo, with: presenter)
    }
  #endif

  /// Shows `flow.url` with `presenter`, then finishes the flow with the callback URL.
  private func present(
    _ flow: OAuthFlow,
    redirectTo: URL?,
    with presenter: some WebAuthPresenter
  ) async throws -> Session {
    // A sign-out while the page is open must win over the callback.
    let signOuts = await sessionStore.signOuts
    let redirectURL = Self.oauthRedirectURL(
      redirectTo: redirectTo, configured: configuration.redirectToURL)

    let callback: URL
    do {
      callback = try await presenter.authenticate(url: flow.url, redirectURL: redirectURL)
    } catch {
      await removeFlow(flow.id)
      throw error
    }

    // The page is closed, so no other code can come back for this flow. Only an exchange that may
    // not have reached the server keeps it, so a retry can still finish it.
    let result: RedirectResult?
    do {
      result = try await handleRedirect(callback, flowID: flow.id, signOuts: signOuts)
    } catch {
      if !Self.mayHaveReachedServer(error) {
        await removeFlow(flow.id)
      }
      throw error
    }

    // A code exchange removed the flow already. Implicit tokens or a non-redirect leave it.
    await removeFlow(flow.id)
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
  /// ``AuthEvent/passwordRecovery`` for ``resetPassword(email:redirectTo:captchaToken:)``,
  /// ``AuthEvent/userUpdated`` for an email change or an identity link, and
  /// ``AuthEvent/signedIn`` otherwise.
  ///
  /// This call is not deduplicated. To handle a redirect URL that can arrive more than once, use
  /// ``handleRedirect(_:)``.
  ///
  /// - Parameters:
  ///   - code: The authorization code from the redirect URL.
  ///   - flowID: The ID of the flow that produced `code`: the ``OAuthFlow/id`` that
  ///     ``oauthSignInURL(_:options:)``, ``linkIdentityURL(_:options:)``, or
  ///     ``ssoSignInURL(_:options:)`` returned. When `nil`, the client tries the pending flows
  ///     newest first.
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
        throw await missingFlowError(
          "No pending flow with ID \(flowID). It finished, expired, or started on another device.",
          signOuts: signOuts)
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
    if let rejection { throw rejection }
    throw await missingFlowError(
      "No pending flow for this code. It finished, expired, or started on another device.",
      signOuts: signOuts)
  }

  /// A sign-out since `signOuts` removed the pending flows. The sign-in then throws
  /// `CancellationError`, as it does when the sign-out lands during the exchange.
  private func missingFlowError(_ message: String, signOuts: UInt64) async -> any Error {
    await sessionStore.signOuts == signOuts
      ? AuthError.oauthFlowFailed(message) : CancellationError()
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

  /// Signs in with a session your app got outside this client, such as tokens that a tvOS app
  /// receives from a sign-in on another device.
  ///
  /// The client reads the expiry from the access token. When the token has expired, it redeems
  /// `refreshToken` for a new session. Otherwise it fetches the user with the access token. Then
  /// it stores the session and emits ``AuthEvent/signedIn`` once. When a request fails, the
  /// stored session stays as it was.
  ///
  /// - Parameters:
  ///   - accessToken: The access token of the session.
  ///   - refreshToken: The refresh token of the session.
  /// - Returns: The stored session.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/jwtVerificationFailed`` when
  ///   `accessToken` is not a JWT with an `exp` claim.
  @discardableResult
  public func importSession(accessToken: String, refreshToken: String) async throws -> Session {
    guard let exp = JWT.decodePayload(accessToken)?["exp"] as? TimeInterval else {
      throw AuthError.jwtVerificationFailed("Invalid JWT structure")
    }

    let now = date()
    let expiresAt = Date(timeIntervalSince1970: exp)
    let session: Session
    if expiresAt <= now {
      session = try await dependencies.refreshRequest(refreshToken)
    } else {
      let user = try await api.execute(authAPI.user(accessToken: accessToken))
      session = Session(
        accessToken: accessToken,
        tokenType: "bearer",
        expiresIn: expiresAt.timeIntervalSince(now),
        expiresAt: exp,
        refreshToken: refreshToken,
        user: user
      )
    }

    try await sessionStore.commit(.signedIn(session, event: .signedIn))
    return session
  }

  /// Ends the sessions that `scope` names.
  ///
  /// - ``SignOutScope/local``, the default, signs out this device. The client removes the
  ///   session, clears every pending PKCE flow, and emits ``AuthEvent/signedOut`` with
  ///   ``SignOutReason/userInitiated`` before it asks the server to revoke the session. So the
  ///   device is signed out whatever the server answers. An error means that the server did not
  ///   revoke the refresh token, which then stays valid until it expires.
  /// - ``SignOutScope/global`` ends every session of the user. The client removes the session
  ///   only after the server ended them. When the request fails, the session stays, so you can
  ///   retry or sign out with `.local`. When the server rejects the refresh of an expired session,
  ///   the client signs out with ``SignOutReason/userInitiated`` and throws. When another sign-in
  ///   replaces the session during that refresh, the client keeps the new session and throws.
  /// - ``SignOutScope/others`` ends every other session of the user. This session stays, and the
  ///   client emits no ``AuthEvent/signedOut``. The client first refreshes an expired session, as
  ///   ``refreshSession()`` does, under every ``AutoRefreshPolicy``. When the server rejects that
  ///   refresh, the client signs out with ``SignOutReason/sessionExpired`` and throws.
  ///
  /// When no session is stored, `.local` and `.global` still clear the local auth state and emit
  /// ``AuthEvent/signedOut``. A sign-out ends refresh tokens only: an access token stays valid
  /// until it expires.
  ///
  /// - Parameter scope: Which sessions to end.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/sessionMissing`` for `.others` when
  ///   no session is stored, or when another sign-in replaced the session during its refresh.
  public func signOut(scope: SignOutScope = .local) async throws {
    if status == .loading {
      try await sessionStore.load()
    }

    if scope != .others {
      // A redirect handled before the sign-out must sign in again when it comes back.
      await dependencies.redirectDeduplicator.removeAll()
    }

    switch scope {
    case .local: try await signOutLocally()
    case .global: try await signOutGlobally()
    case .others: try await signOutOthers()
    }
  }

  private func signOutLocally() async throws {
    await removePendingFlows()
    let removed = try await sessionStore.signOut(.userInitiated)
    await dependencies.redirectDeduplicator.removeAll()
    guard let removed else { return }

    var accessToken = removed.session.accessToken
    if removed.isExpired(at: date(), leeway: defaultExpiryMargin) {
      do {
        accessToken = try await dependencies.refreshRequest(removed.session.refreshToken)
          .accessToken
      } catch let error as AuthError where error.endsSessionForGood {
        return
      }
    }
    try await logout(accessToken: accessToken, scope: .local)
  }

  private func signOutGlobally() async throws {
    guard let held = currentSession else {
      return try await removeSession(refreshToken: nil)
    }

    var session = held
    if sessionStore.validSession(minimumValidity: defaultExpiryMargin) == nil {
      do {
        session = try await sessionStore.refreshHeldSession(
          readWith: held.refreshToken,
          requiringSameSession: true,
          using: dependencies.refreshRequest,
          signOutReason: { $0.isClientError ? .userInitiated : nil }
        )
      } catch let error as AuthError where error.isClientError {
        await removePendingFlows()
        await dependencies.redirectDeduplicator.removeAll()
        throw error
      } catch  where currentSession == nil && !Task.isCancelled {
        // Another sign-out landed during the refresh, so no session is left to revoke.
        return try await removeSession(refreshToken: nil)
      }
    }

    try await logout(accessToken: session.accessToken, scope: .global)
    try await removeSession(refreshToken: session.refreshToken)
  }

  private func signOutOthers() async throws {
    guard var session = currentSession else { throw AuthError.sessionMissing }
    if sessionStore.validSession(minimumValidity: defaultExpiryMargin) == nil {
      session = try await sessionStore.refreshHeldSession(
        readWith: session.refreshToken, requiringSameSession: true,
        using: dependencies.refreshRequest)
    }
    try await logout(accessToken: session.accessToken, scope: .others)
  }

  /// Signs out while the store holds the session whose refresh token was `refreshToken`, or a
  /// refresh of it, or holds none when `refreshToken` is `nil`. A sign-in that landed during the
  /// request stays.
  private func removeSession(refreshToken: String?) async throws {
    await removePendingFlows()
    try await sessionStore.commit(.revoked(.userInitiated, refreshToken: refreshToken))
    // A redirect cached between the first clear and the commit must not replay either.
    await dependencies.redirectDeduplicator.removeAll()
  }

  /// A storage error is logged: it must not stop the sign-out.
  private func removePendingFlows() async {
    do {
      try await dependencies.flowStore.removeAll()
    } catch {
      configuration.logger.error("Failure removing pending flows: \(error.localizedDescription)")
    }
  }

  /// Sends `POST /logout`. Each scope decides what happens to the local session.
  private func logout(accessToken: String, scope: SignOutScope) async throws {
    do {
      try await api.execute(authAPI.signOut(accessToken: accessToken, scope: scope))
    } catch let error as AuthError where error.meansNothingLeftToRevoke(for: scope) {}
  }

  /// Verifies a one-time code from an email, and stores the session.
  ///
  /// The client emits one auth event, chosen by `type`: ``AuthEvent/passwordRecovery`` for
  /// ``EmailOTPType/recovery``, ``AuthEvent/userUpdated`` for an ``EmailOTPType/emailChange`` of
  /// the signed-in user, and ``AuthEvent/signedIn`` otherwise. The first confirmation of a secure
  /// email change returns ``VerifyOTPResult/emailChangePending(message:)``, with no session and no
  /// event.
  ///
  /// - Parameters:
  ///   - email: The email address that got the code.
  ///   - token: The code from the email.
  ///   - type: The kind of email that sent the code.
  /// - Returns: The session, or the pending state of a secure email change.
  @discardableResult
  public func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType
  ) async throws -> VerifyOTPResult {
    try await _verifyOTP(
      authAPI.verifyOTP(email: email, token: token, type: type),
      type: type
    )
  }

  /// Verifies a one-time code from an SMS or WhatsApp message, and stores the session.
  ///
  /// The client emits ``AuthEvent/userUpdated`` for a ``PhoneOTPType/phoneChange`` of the
  /// signed-in user, and ``AuthEvent/signedIn`` otherwise.
  ///
  /// - Parameters:
  ///   - phone: The phone number that got the code.
  ///   - token: The code from the message.
  ///   - type: The kind of message that sent the code.
  /// - Returns: The session.
  @discardableResult
  public func verifyOTP(
    phone: String,
    token: String,
    type: PhoneOTPType
  ) async throws -> Session {
    let session = try await api.execute(
      authAPI.verifyOTP(phone: phone, token: token, type: type))
    try await sessionStore.commit(
      type == .phoneChange ? .userChangeVerified(session) : .signedIn(session, event: .signedIn))
    return session
  }

  /// Verifies the token hash of an email link, and stores the session.
  ///
  /// Use it when your email template links to your own page with `{{ .TokenHash }}`. The client
  /// emits the same events as ``verifyOTP(email:token:type:)``.
  ///
  /// - Parameters:
  ///   - tokenHash: The token hash from the link.
  ///   - type: The kind of email that sent the link.
  /// - Returns: The session, or the pending state of a secure email change.
  @discardableResult
  public func verifyOTP(
    tokenHash: String,
    type: EmailOTPType
  ) async throws -> VerifyOTPResult {
    try await _verifyOTP(
      authAPI.verifyOTP(tokenHash: tokenHash, type: type),
      type: type
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
    _ request: AuthRequest<VerifyOTPResult>,
    type: EmailOTPType
  ) async throws -> VerifyOTPResult {
    let result = try await api.execute(request)

    if case .signedIn(let session) = result {
      try await sessionStore.commit(Self.verifiedTransition(session, for: type))
    }

    return result
  }

  /// Sends a sign-up confirmation or an email change confirmation again.
  ///
  /// The client stores a new PKCE flow for the link before the request. The call succeeds for an
  /// unknown email too, so it does not show which addresses have an account.
  ///
  /// - Parameters:
  ///   - email: The email address to send to.
  ///   - type: The kind of email to send again.
  ///   - redirectTo: The URL the link redirects to. When `nil`, the client uses
  ///     ``Configuration/redirectToURL``.
  ///   - captchaToken: The captcha verification token.
  public func resend(
    email: String,
    type: ResendEmailType,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await withFlow(type == .emailChange ? .emailChange : .signIn, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.resend(
          email: email,
          type: type,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
    }
  }

  /// Sends a phone sign-in code or a phone change code again.
  ///
  /// The call succeeds for an unknown phone number too, so it does not show which numbers have an
  /// account.
  ///
  /// - Parameters:
  ///   - phone: The phone number to send to, with the international prefix.
  ///   - type: The kind of code to send again.
  ///   - captchaToken: The captcha verification token.
  /// - Returns: The ID that the SMS provider gave the message, or `nil` when the provider sent
  ///   none.
  @discardableResult
  public func resend(
    phone: String,
    type: ResendPhoneType,
    captchaToken: String? = nil
  ) async throws -> MessageID? {
    try await api.execute(authAPI.resend(phone: phone, type: type, captchaToken: captchaToken))
  }

  /// Sends a one-time code to the email or phone of the signed-in user.
  ///
  /// Pass the code as ``UserAttributes/nonce`` to ``updateUser(_:redirectTo:)`` when the project
  /// needs a recent sign-in to change the password.
  public func reauthenticate() async throws {
    try await api.authorizedExecute { authAPI.reauthenticate(accessToken: $0) }
  }

  /// Fetches the signed-in user from the Auth server.
  ///
  /// The client sends the access token of the current session. It refreshes the session first
  /// when the access token has expired. Use this method when you need the latest user data. For a
  /// value without a request, read ``currentUser``.
  ///
  /// - Returns: The signed-in user.
  /// - Throws: ``AuthError/sessionMissing`` when no user is signed in. Else the error of the
  ///   refresh or of the request.
  public func user() async throws -> User {
    try await api.authorizedExecute { authAPI.user(accessToken: $0) }
  }

  /// Fetches the user that an access token belongs to.
  ///
  /// The client sends `jwt` as is. It does not refresh it. When `jwt` is the access token of the
  /// current session and the Auth server reports that its session no longer exists, the client
  /// signs out.
  ///
  /// - Parameter jwt: The access token to send.
  /// - Returns: The user that `jwt` belongs to.
  /// - Throws: The error of the request, for example when the Auth server rejects `jwt`.
  public func user(jwt: String) async throws -> User {
    try await api.execute(
      authAPI.user(accessToken: jwt), for: sessionOwnership(ofAccessToken: jwt))
  }

  private func sessionOwnership(ofAccessToken accessToken: String) -> SessionOwnership {
    guard let stored = currentSession, stored.accessToken == accessToken else { return .unscoped }
    return .snapshot(stored)
  }

  /// Updates the signed-in user.
  ///
  /// The client merges the returned user into the current session and emits
  /// ``AuthEvent/userUpdated``. It keeps the tokens of the current session, also when a refresh
  /// rotates them while the request is in flight.
  ///
  /// Set ``UserAttributes/currentPassword`` when you change the password and the project requires
  /// the current password for that change. When `attributes` changes the email, the client starts
  /// an email change flow. Pass the redirect URL that comes back to ``handleRedirect(_:)``.
  ///
  /// - Parameters:
  ///   - attributes: The values to change.
  ///   - redirectTo: The URL that the confirmation link of an email change opens.
  /// - Returns: The updated user.
  /// - Throws: ``AuthError/sessionMissing`` when no user is signed in. Else the error of the
  ///   request.
  @discardableResult
  public func updateUser(
    _ attributes: UserAttributes,
    redirectTo: URL? = nil
  ) async throws -> User {
    guard attributes.email != nil else {
      return try await sendUserUpdate(attributes, redirectTo: redirectTo, pkce: nil)
    }
    return try await withFlow(.emailChange, redirectTo: redirectTo) {
      try await sendUserUpdate(attributes, redirectTo: redirectTo, pkce: $0.challenge)
    }
  }

  private func sendUserUpdate(
    _ attributes: UserAttributes,
    redirectTo: URL?,
    pkce: PKCEChallenge?
  ) async throws -> User {
    let updatedUser = try await api.authorizedExecute {
      try authAPI.updateUser(attributes, redirectTo: redirectTo, pkce: pkce, accessToken: $0)
    }
    try await sessionStore.commit(.userUpdated(updatedUser, event: .userUpdated))
    return updatedUser
  }

  /// Fetches the identities linked to the signed-in user.
  ///
  /// The client sends a request through ``user()``.
  ///
  /// - Returns: The linked identities. Empty when the server sends none.
  /// - Throws: ``AuthError/sessionMissing`` when no user is signed in. Else the error of the
  ///   refresh or of the request.
  public func identities() async throws -> [UserIdentity] {
    try await user().identities ?? []
  }

  /// Links an identity to the signed-in user with an ID token that a third-party identity
  /// provider issued.
  ///
  /// The client stores the returned session and emits ``AuthEvent/userUpdated``.
  ///
  /// - Parameter credentials: The ID token and the values the server needs to check it.
  /// - Returns: The new session.
  /// - Throws: ``AuthError/sessionMissing`` when no user is signed in. Else the error of the
  ///   request.
  @discardableResult
  public func linkIdentity(idToken credentials: IDTokenCredentials) async throws -> Session {
    let session = try await api.execute(
      authAPI.signInWithIDToken(credentials: credentials, linkingTo: session().accessToken)
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
  /// - Returns: The flow that this call started: the URL to open, and the flow ID.
  public func linkIdentityURL(
    _ provider: Provider,
    options: OAuthOptions = .init()
  ) async throws -> OAuthFlow {
    let redirectTo = Self.oauthRedirectURL(
      redirectTo: options.redirectTo, configured: configuration.redirectToURL)
    return try await withFlow(.linkIdentity, redirectTo: redirectTo, sendsEmail: false) {
      started in
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
      return OAuthFlow(id: started.flow.id, url: url)
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
        linkIdentityURL(provider, options: options), redirectTo: options.redirectTo,
        with: presenter)
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
        linkIdentityURL(provider, options: options), redirectTo: options.redirectTo,
        with: presenter)
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
      .identityUnlinked(identity.id, userID: identity.userID))
  }

  /// Sends a password reset email.
  ///
  /// The email holds a link, or a code when the template uses `{{ .Token }}`. Pass the redirect
  /// URL of the link to ``handleRedirect(_:)``, or the code to
  /// ``verifyOTP(email:token:type:)`` with ``EmailOTPType/recovery``. Both sign the
  /// user in and emit ``AuthEvent/passwordRecovery``. Then set the new password with
  /// ``updateUser(_:redirectTo:)``.
  ///
  /// The call succeeds for an unknown email too, so it does not show which addresses have an
  /// account.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - redirectTo: The URL the link redirects to. When `nil`, the client uses
  ///     ``Configuration/redirectToURL``.
  ///   - captchaToken: The captcha verification token.
  public func resetPassword(
    email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await withFlow(.recovery, redirectTo: redirectTo) {
      try await api.execute(
        authAPI.resetPassword(
          email: email,
          redirectTo: redirectTo,
          captchaToken: captchaToken,
          pkce: $0.challenge
        )
      )
    }
  }

  /// Refreshes the session, whatever its expiry, and returns it.
  ///
  /// When a concurrent refresh or sign-in replaced the session during this call, and the new
  /// session is still valid, this method returns the new session without a request. To sign in
  /// with tokens from elsewhere, use ``importSession(accessToken:refreshToken:)``.
  ///
  /// - Returns: A new session, or the valid session that replaced the current one.
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored.
  @discardableResult
  public func refreshSession() async throws -> Session {
    try await sessionManager.refreshSession()
  }

  /// Refreshes the session, unless a concurrent refresh or sign-in already replaced `session`.
  ///
  /// The check runs in the session store, together with the refresh, so a refresh that commits
  /// after the caller read `session` is never repeated with the rotated refresh token.
  ///
  /// - Parameter session: The session the caller read, such as the one it signed a request with.
  /// - Returns: A new session, or the valid session that replaced `session`.
  /// - Throws: ``AuthError/sessionMissing`` when there is no current session.
  package func refreshSession(replacing session: Session) async throws -> Session {
    try await sessionManager.refreshHeldSession(session.refreshToken)
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
  /// - Parameter sendsEmail: Whether the request sends an email with a link. Only then can a
  ///   code come back for the flow after the request fails, so only then does a failure that may
  ///   have reached the server keep the flow.
  private func withFlow<Result>(
    _ purpose: PendingFlowRecord.Purpose,
    redirectTo: URL?,
    sendsEmail: Bool = true,
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
      if !sendsEmail || !Self.mayHaveReachedServer(error) {
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

  /// Verifies the access token of the current session and returns its claims.
  ///
  /// The token comes from ``session()``, so an expired session is refreshed first. The token is
  /// then verified as ``claims(jwt:options:)`` describes.
  ///
  /// - Parameter options: Options that change how the token is verified.
  /// - Returns: The verified claims, with the token's header and signature.
  /// - Throws: Every error that ``session()`` throws, unchanged: for example, an error of kind
  ///   ``AuthError/Kind-swift.struct/sessionMissing`` when no user is signed in, or the refresh
  ///   error when the server rejects the refresh. An error of kind
  ///   ``AuthError/Kind-swift.struct/jwtVerificationFailed`` when verification fails.
  public func claims(options: ClaimsOptions = .init()) async throws -> VerifiedClaims {
    try await claims(jwt: session().accessToken, options: options)
  }

  /// Verifies a JSON Web Token and returns its claims.
  ///
  /// A token signed with an asymmetric key, such as ES256 or RS256, that names its key in the
  /// `kid` header is verified on the device against the project's JSON Web Key Set at
  /// `/.well-known/jwks.json`. Each client caches the key set for 10 minutes, so most calls send
  /// no request. Prefer this method over ``user(jwt:)``, which sends a request for each token.
  ///
  /// The Auth server verifies every other token through ``user(jwt:)``: a token signed with a
  /// symmetric key (HS256), a token without a `kid`, and a token whose key the client cannot find.
  ///
  /// - Parameters:
  ///   - jwt: The token to verify.
  ///   - options: Options that change how the token is verified.
  /// - Returns: The verified claims, with the token's header and signature.
  /// - Throws: An error of kind ``AuthError/Kind-swift.struct/jwtVerificationFailed`` when the
  ///   token is malformed, has no `exp` or `sub` claim, has expired (unless
  ///   ``ClaimsOptions/allowsExpired`` is `true`), or has an invalid signature. The client checks
  ///   the structure and the `exp` and `sub` claims before it sends any request. The error of
  ///   ``user(jwt:)`` when the Auth server rejects the token.
  public func claims(jwt: String, options: ClaimsOptions = .init()) async throws -> VerifiedClaims {
    guard let decodedJWT = JWT.decode(jwt) else {
      throw AuthError.jwtVerificationFailed("Invalid JWT structure")
    }

    let claims = try VerifiedClaims(decodedJWT)
    if !options.allowsExpired, claims.expiresAt <= date() {
      throw AuthError.jwtVerificationFailed("JWT has expired")
    }

    guard
      let signingKey = try await signingKey(for: claims.header, options: options),
      let isValid = JWTVerifier.verify(decodedJWT, with: signingKey)
    else {
      _ = try await user(jwt: jwt)
      return claims
    }

    guard isValid else {
      throw AuthError.jwtVerificationFailed("Invalid JWT signature")
    }
    return claims
  }

  private func signingKey(for header: JWTHeader, options: ClaimsOptions) async throws -> JWK? {
    guard !header.alg.hasPrefix("HS"), let kid = header.kid else {
      return nil
    }
    if let key = options.jwks?.key(for: kid) {
      return key
    }
    return try await jwksCache.key(for: kid)
  }
}

extension AuthError {
  /// Whether a logout answer means the server has nothing left to revoke for `scope`.
  fileprivate func meansNothingLeftToRevoke(for scope: SignOutScope) -> Bool {
    guard response?.statusCode == 403 else { return false }
    return errorCode == .userNotFound || (scope == .local && errorCode == .sessionNotFound)
  }
}
