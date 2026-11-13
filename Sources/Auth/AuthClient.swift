import ConcurrencyExtras
public import Foundation
import IssueReporting

import struct HTTPTypes.HTTPFields

#if canImport(AuthenticationServices)
  public import AuthenticationServices
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

struct AuthClientLoggerDecorator: SupabaseLogger {
  let clientID: AuthClientID
  let decoratee: any SupabaseLogger

  func log(message: SupabaseLogMessage) {
    var message = message
    message.additionalContext["client_id"] = .integer(clientID)
    decoratee.log(message: message)
  }
}

/// JWKS cache TTL (Time To Live) - 10 minutes
private let JWKS_TTL: TimeInterval = 10 * 60

/// Cached JWKS value with timestamp
private struct CachedJWKS {
  let jwks: JWKS
  let cachedAt: Date
}

/// Global JWKS cache shared across all clients with the same storage key.
/// This is especially useful for shared-memory execution environments such as
/// AWS Lambda or serverless functions. Regardless of how many clients are created,
/// if they share the same storage key they will use the same JWKS cache,
/// significantly speeding up getClaims() with asymmetric JWTs.
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
/// authentication-state changes. It is an `actor`, so all mutable state is protected by Swift
/// concurrency.
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
/// - ``exchangeCodeForSession(authCode:)``
/// - ``session(from:)``
/// - ``setSession(accessToken:refreshToken:)``
/// - ``refreshSession(refreshToken:)``
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
/// - ``getLinkIdentityURL(provider:scopes:redirectTo:queryParams:)``
/// - ``unlinkIdentity(_:)``
///
/// ### JWT claims
/// - ``getClaims(jwt:options:)``
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
public actor AuthClient {
  private static let _globalClientID = LockIsolated(0)

  /// Thread-safe auto-incrementing client ID generator.
  private static func nextClientID() -> AuthClientID {
    _globalClientID.withValue { value in
      value += 1
      return value
    }
  }

  nonisolated let clientID: AuthClientID

  nonisolated private var api: APIClient { Dependencies[clientID].api }

  nonisolated var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }

  nonisolated private var codeVerifierStorage: CodeVerifierStorage {
    Dependencies[clientID].codeVerifierStorage
  }

  nonisolated private var date: @Sendable () -> Date { Dependencies[clientID].date }
  nonisolated private var sessionManager: SessionManager { Dependencies[clientID].sessionManager }
  nonisolated private var eventEmitter: AuthStateChangeEventEmitter {
    Dependencies[clientID].eventEmitter
  }
  nonisolated private var logger: (any SupabaseLogger)? {
    Dependencies[clientID].configuration.logger
  }
  nonisolated private var sessionStorage: SessionStorage { Dependencies[clientID].sessionStorage }
  nonisolated private var pkce: PKCE { Dependencies[clientID].pkce }

  #if canImport(ObjectiveC) && canImport(Combine)
    @MainActor
    private var appLifecycleCancellables = Set<AnyCancellable>()
  #endif

  /// Returns the session, refreshing it if necessary.
  ///
  /// If no session can be found, a ``AuthError/sessionMissing`` error is thrown.
  @available(*, deprecated, message: "Use session() instead.")
  public var session: Session {
    get async throws {
      try await sessionManager.session()
    }
  }

  /// Returns the session, refreshing it first when it is expired or about to expire.
  ///
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or the error of the
  ///   refresh.
  public func session() async throws -> Session {
    try await sessionManager.session()
  }

  /// Returns the current session, if any.
  ///
  /// The session returned by this property may be expired. Use ``session`` for a session that is guaranteed to be valid.
  nonisolated public var currentSession: Session? {
    sessionStorage.get()
  }

  /// Returns the current user, if any.
  ///
  /// The user returned by this property may be outdated. Use ``user(jwt:)`` method to get an up-to-date user instance.
  nonisolated public var currentUser: User? {
    currentSession?.user
  }

  /// Namespace for accessing multi-factor authentication API.
  nonisolated public var mfa: AuthMFA {
    AuthMFA(clientID: clientID)
  }

  /// Namespace for the GoTrue admin methods.
  /// - Warning: This methods requires `secret` key, be careful to never expose `secret`
  /// key in the client.
  nonisolated public var admin: AuthAdmin {
    AuthAdmin(clientID: clientID)
  }

  /// Namespace for the OAuth 2.1 authorization server consent and grant-management API.
  nonisolated public var oauthServer: AuthOAuthServer {
    AuthOAuthServer(clientID: clientID)
  }

  /// Initializes a AuthClient with a specific configuration.
  ///
  /// - Parameters:
  ///   - configuration: The client configuration.
  public init(configuration: Configuration) {
    clientID = AuthClient.nextClientID()

    Dependencies[clientID] = Dependencies(
      configuration: configuration,
      http: HTTPClient(configuration: configuration),
      api: APIClient(clientID: clientID),
      codeVerifierStorage: .live(clientID: clientID),
      sessionStorage: .live(clientID: clientID),
      sessionManager: .live(clientID: clientID),
      logger: configuration.logger.map {
        AuthClientLoggerDecorator(clientID: clientID, decoratee: $0)
      }
    )

    Task { @MainActor in observeAppLifecycleChanges() }
  }

  deinit {
    // Grab the session manager before dropping the dependencies entry, and capture only it in the
    // task below, capturing `self` would resurrect this client while it is being deallocated.
    let sessionManager = Dependencies.instances.value[clientID]?.sessionManager

    Dependencies.instances.withValue { $0.removeValue(forKey: clientID) }

    // The auto-refresh loop retains the session manager, so it keeps ticking forever unless it is
    // explicitly stopped. `observeAppLifecycleChanges()` only stops it when the app resigns active,
    // which never happens for short-lived clients, or when auto-refresh was started manually.
    Task { await sessionManager?.stopAutoRefresh() }
  }

  #if canImport(ObjectiveC) && canImport(Combine)
    @MainActor
    private func observeAppLifecycleChanges() {
      var didBecomeActiveNotification: NSNotification.Name?
      var willResignActiveNotification: NSNotification.Name?

      #if canImport(UIKit)
        #if canImport(WatchKit)
          didBecomeActiveNotification = WKExtension.applicationDidBecomeActiveNotification
          willResignActiveNotification = WKExtension.applicationWillResignActiveNotification
        #else
          didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
          willResignActiveNotification = UIApplication.willResignActiveNotification
        #endif
      #elseif canImport(AppKit)
        didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
        willResignActiveNotification = NSApplication.willResignActiveNotification
      #endif

      if let didBecomeActiveNotification, let willResignActiveNotification {
        NotificationCenter.default
          .publisher(for: didBecomeActiveNotification)
          .sink { [weak self] _ in
            Task {
              await self?.handleDidBecomeActive()
            }
          }
          .store(in: &appLifecycleCancellables)

        NotificationCenter.default
          .publisher(for: willResignActiveNotification)
          .sink { [weak self] _ in
            Task {
              await self?.handleWillResignActive()
            }
          }
          .store(in: &appLifecycleCancellables)
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
  /// - Note: The session emitted in the  ``AuthChangeEvent/initialSession`` event may have been expired
  /// since last launch, consider checking for ``Session/isExpired``. If this is the case, then expect a ``AuthChangeEvent/tokenRefreshed`` after.
  @available(*, deprecated, message: "Use events() instead.")
  @discardableResult
  public func onAuthStateChange(
    _ listener: @escaping AuthStateChangeListener
  ) async -> some AuthStateChangeListenerRegistration {
    let token = eventEmitter.attach(listener)
    await emitInitialSession(forToken: token)
    return token
  }

  /// Whether a user is signed in, read from the session that the client holds in storage.
  ///
  /// The session may be expired; check ``Session/isExpired(at:leeway:)``. This version of the
  /// client never reports ``AuthStatus/loading``, and it does not record a ``SignOutReason``.
  nonisolated public var status: AuthStatus {
    currentSession.map(AuthStatus.signedIn) ?? .signedOut(nil)
  }

  /// The changes of the auth status, starting with ``AuthChangeEvent/initialSession``.
  ///
  /// ```swift
  /// for await change in supabase.auth.events() {
  ///   switch change.status {
  ///   case .signedIn(let session): show(session.user)
  ///   case .signedOut, .loading: showSignIn()
  ///   }
  /// }
  /// ```
  ///
  /// Each call returns a new stream. The stream does not finish on its own; cancel the task that
  /// consumes it.
  ///
  /// The status of each change agrees with ``status``: a session that is still stored is reported
  /// as ``AuthStatus/signedIn(_:)``, also when it is expired. Check
  /// ``Session/isExpired(at:leeway:)``. With ``Configuration/emitLocalSessionAsInitialSession``
  /// set to `false` (the default), the client tries to refresh an expired session before the
  /// first change. When that refresh fails and the session stays in storage, for example with no
  /// network, the first change carries the expired session. With the value `true`, the first
  /// change carries the stored session at once and ``AuthChangeEvent/tokenRefreshed`` follows a
  /// successful refresh.
  ///
  /// This version of the client does not record why a session ended, so
  /// ``AuthChange/signOutReason`` is always `nil`.
  nonisolated public func events() -> AsyncStream<AuthChange> {
    let (stream, continuation) = AsyncStream<AuthChange>.makeStream()

    let token = eventEmitter.attach { [weak self] event, session in
      // The v2 emitter sends no session when the refresh at start fails, for example offline.
      // The session is still stored then, so the change must not report a sign-out.
      let session = session ?? (event == .signedOut ? nil : self?.currentSession)
      continuation.yield(
        AuthChange(event: event, status: session.map(AuthStatus.signedIn) ?? .signedOut(nil)))
    }
    continuation.onTermination = { _ in token.cancel() }
    Task { await emitInitialSession(forToken: token) }

    return stream
  }

  /// Listen for auth state changes.
  ///
  /// An `.initialSession` is always emitted when this method is called.
  @available(*, deprecated, message: "Use events() instead.")
  nonisolated public var authStateChanges:
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
  ///   - redirectTo: The redirect URL embedded in the email link, defaults to ``Configuration/redirectTo`` if not provided.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  @available(*, deprecated, message: "Use signUp(email:password:options:) instead.")
  public func signUp(
    email: String,
    password: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _signUp(
      email: email, password: password, data: data, redirectTo: redirectTo,
      captchaToken: captchaToken)
  }

  /// Creates a new user with an email and a password.
  ///
  /// When the project needs no email confirmation, the user is signed in and the client stores
  /// the session. Otherwise the server sends a confirmation email.
  ///
  /// A call with no `options` argument and no result type selects the deprecated overload that
  /// returns ``AuthResponse``. Pass `options`, or give the result the type ``SignUpResult``.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - password: The user's password.
  ///   - options: The user metadata, the redirect URL, and the captcha token.
  /// - Returns: The session, or the user who must confirm first.
  @_disfavoredOverload
  public func signUp(
    email: String,
    password: String,
    options: SignUpOptions = .init()
  ) async throws -> SignUpResult {
    SignUpResult(
      try await _signUp(
        email: email, password: password, data: options.userMetadata,
        redirectTo: options.redirectTo, captchaToken: options.captchaToken))
  }

  private func _signUp(
    email: String,
    password: String,
    data: [String: AnyJSON]?,
    redirectTo: URL?,
    captchaToken: String?
  ) async throws -> AuthResponse {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await _signUp(
      request: .init(
        url: configuration.url.appendingPathComponent("signup"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
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
  ///   - channel: Messaging channel to use (e.g. whatsapp or sms).
  ///   - data: Custom data object to store additional user metadata.
  ///   - captchaToken: Optional captcha token for securing this endpoint.
  @discardableResult
  @available(*, deprecated, message: "Use signUp(phone:password:options:) instead.")
  public func signUp(
    phone: String,
    password: String,
    channel: MessagingChannel = .sms,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws -> AuthResponse {
    try await _signUp(
      phone: phone, password: password, channel: channel, data: data, captchaToken: captchaToken)
  }

  /// Creates a new user with a phone number and a password.
  ///
  /// When the project needs no phone confirmation, the user is signed in and the client stores
  /// the session. Otherwise the server sends a confirmation code.
  ///
  /// A call with no `options` argument and no result type selects the deprecated overload that
  /// returns ``AuthResponse``. Pass `options`, or give the result the type ``SignUpResult``.
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the country code.
  ///   - password: The user's password.
  ///   - options: The user metadata, the channel, and the captcha token.
  /// - Returns: The session, or the user who must confirm first.
  @_disfavoredOverload
  public func signUp(
    phone: String,
    password: String,
    options: SignUpOptions = .init()
  ) async throws -> SignUpResult {
    SignUpResult(
      try await _signUp(
        phone: phone, password: password, channel: options.channel, data: options.userMetadata,
        captchaToken: options.captchaToken))
  }

  private func _signUp(
    phone: String,
    password: String,
    channel: MessagingChannel,
    data: [String: AnyJSON]?,
    captchaToken: String?
  ) async throws -> AuthResponse {
    try await _signUp(
      request: .init(
        url: configuration.url.appendingPathComponent("signup"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          SignUpRequest(
            password: password,
            phone: phone,
            channel: channel,
            data: data,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
  }

  private func _signUp(request: HTTPRequest) async throws -> AuthResponse {
    let response = try await api.execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.resolvedDecoder
    )

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
  ) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.resolvedEncoder.encode(
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
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "password")],
        body: configuration.resolvedEncoder.encode(
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
  @available(*, deprecated, message: "Use signInWithIDToken(_:) instead.")
  @discardableResult
  public func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "id_token")],
        body: configuration.resolvedEncoder.encode(credentials)
      )
    )
  }

  /// Signs in with an ID token that a third-party identity provider issued, such as Sign in with
  /// Apple or Google Sign-In.
  ///
  /// The server checks the token and creates the user if needed.
  ///
  /// ```swift
  /// try await client.auth.signInWithIDToken(
  ///   IDTokenCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
  /// )
  /// ```
  ///
  /// - Parameter credentials: The ID token and the values the server needs to check it.
  /// - Returns: The new session.
  @discardableResult
  public func signInWithIDToken(_ credentials: IDTokenCredentials) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "id_token")],
        body: configuration.resolvedEncoder.encode(IDTokenGrantBody(credentials))
      )
    )
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
  ///
  /// - Parameter credentials: The chain, the signed message, and its signature.
  /// - Returns: The new session.
  @discardableResult
  public func signInWithWeb3(_ credentials: Web3Credentials) async throws -> Session {
    try await _signIn(
      request: .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "web3")],
        body: configuration.resolvedEncoder.encode(credentials)
      )
    )
  }

  /// Signs in a user via a signed Sign in with Ethereum (EIP-4361) or Sign in with Solana message.
  @available(*, deprecated, message: "Use signInWithWeb3(_:) instead.")
  @discardableResult
  public func signInWithWeb3(credentials: Web3Credentials) async throws -> Session {
    try await signInWithWeb3(credentials)
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
        body: configuration.resolvedEncoder.encode(
          SignUpRequest(
            data: data,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) }
          )
        )
      )
    )
  }

  private func _signIn(request: HTTPRequest) async throws -> Session {
    let session = try await api.execute(request).decoded(
      as: Session.self,
      decoder: configuration.resolvedDecoder
    )

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
  @available(*, deprecated, message: "Use signInWithOTP(email:options:) instead.")
  public func signInWithOTP(
    email: String,
    redirectTo: URL? = nil,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await _signInWithOTP(
      email: email, redirectTo: redirectTo, shouldCreateUser: shouldCreateUser, data: data,
      captchaToken: captchaToken)
  }

  /// Sends a one-time code or a magic link to an email address.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - options: Whether to create the user, the user metadata, the redirect URL, and the
  ///     captcha token. Pass it to select this method: a call with only `email:` selects the
  ///     deprecated method and keeps its request.
  @_disfavoredOverload
  public func signInWithOTP(
    email: String,
    options: EmailOTPOptions = .init()
  ) async throws {
    try await _signInWithOTP(
      email: email, redirectTo: options.redirectTo, shouldCreateUser: options.shouldCreateUser,
      data: options.userMetadata, captchaToken: options.captchaToken)
  }

  private func _signInWithOTP(
    email: String,
    redirectTo: URL?,
    shouldCreateUser: Bool,
    data: [String: AnyJSON]?,
    captchaToken: String?
  ) async throws {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("otp"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
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
  /// - Note: You need to configure a WhatsApp sender on Twilio if you are using phone sign in with the `whatsapp` channel.
  @available(*, deprecated, message: "Use signInWithOTP(phone:options:) instead.")
  public func signInWithOTP(
    phone: String,
    channel: MessagingChannel = .sms,
    shouldCreateUser: Bool = true,
    data: [String: AnyJSON]? = nil,
    captchaToken: String? = nil
  ) async throws {
    _ = try await _signInWithOTP(
      phone: phone, channel: channel, shouldCreateUser: shouldCreateUser, data: data,
      captchaToken: captchaToken)
  }

  /// Sends a one-time code to a phone number.
  ///
  /// A call with no `options` argument and no result type selects the deprecated overload that
  /// returns nothing. Pass `options`, or give the result the type `MessageID?`.
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the country code.
  ///   - options: Whether to create the user, the user metadata, the channel, and the captcha
  ///     token.
  /// - Returns: The ID that the SMS provider gave the message, when the server sends one.
  @_disfavoredOverload
  @discardableResult
  public func signInWithOTP(
    phone: String,
    options: PhoneOTPOptions = .init()
  ) async throws -> MessageID? {
    try await _signInWithOTP(
      phone: phone, channel: options.channel, shouldCreateUser: options.shouldCreateUser,
      data: options.userMetadata, captchaToken: options.captchaToken)
  }

  private func _signInWithOTP(
    phone: String,
    channel: MessagingChannel,
    shouldCreateUser: Bool,
    data: [String: AnyJSON]?,
    captchaToken: String?
  ) async throws -> MessageID? {
    let response = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("otp"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
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
    // The v2 method ignored this body, so a body that does not decode must not fail the call.
    return (try? response.decoded(as: MessageIDBody.self, decoder: configuration.resolvedDecoder))?
      .messageId
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
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("sso"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          SignInWithSSORequest(
            providerId: nil,
            domain: domain,
            redirectTo: redirectTo ?? configuration.redirectTo,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            skipHttpRedirect: true
          )
        )
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
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
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    return try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("sso"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          SignInWithSSORequest(
            providerId: providerId,
            domain: nil,
            redirectTo: redirectTo ?? configuration.redirectTo,
            gotrueMetaSecurity: captchaToken.map { AuthMetaSecurity(captchaToken: $0) },
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            skipHttpRedirect: true
          )
        )
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Log in an existing user by exchanging an Auth Code issued during the PKCE flow.
  public func exchangeCodeForSession(authCode: String) async throws -> Session {
    let codeVerifier = codeVerifierStorage.get()

    if codeVerifier == nil, configuration.flowType == .pkce {
      throw AuthError.pkceGrantCodeExchange(
        message:
          "PKCE code verifier not found. The flow was started on another device, its verifier was evicted or already used, or the storage was cleared."
      )
    }

    let session: Session = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "pkce")],
        body: configuration.resolvedEncoder.encode(
          [
            "auth_code": authCode,
            "code_verifier": codeVerifier,
          ]
        )
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)

    codeVerifierStorage.set(nil)

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
  nonisolated public func getOAuthSignInURL(
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
    let url = try getOAuthSignInURL(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo ?? configuration.redirectTo,
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
        try await withCheckedThrowingContinuation { [configuration] continuation in
          guard let callbackScheme = (configuration.redirectTo ?? redirectTo)?.scheme else {
            preconditionFailure(
              "Please, provide a valid redirect URL, either through `redirectTo` param, or globally through `AuthClient.Configuration.redirectToURL`."
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
  nonisolated public func handle(_ url: URL) {
    Task {
      do {
        try await session(from: url)
      } catch {
        logger?.error("Failure loading session from url '\(url)' error: \(error)")
      }
    }
  }

  /// Gets the session data from a OAuth2 callback URL.
  @discardableResult
  public func session(from url: URL) async throws -> Session {
    logger?.debug("Received URL: \(url)")

    let params = extractParams(from: url)

    switch configuration.flowType {
    case .implicit:
      guard isImplicitGrantFlow(params: params) else {
        throw AuthError.implicitGrantRedirect(
          message: "Not a valid implicit grant flow URL: \(url)"
        )
      }
      return try await handleImplicitGrantFlow(params: params)

    case .pkce:
      guard isPKCEFlow(params: params) else {
        throw AuthError.pkceGrantCodeExchange(message: "Not a valid PKCE flow URL: \(url)")
      }
      return try await handlePKCEFlow(params: params)
    }
  }

  private func handleImplicitGrantFlow(params: [String: String]) async throws -> Session {
    precondition(configuration.flowType == .implicit, "Method only allowed for implicit flow.")

    if let errorMessage = params["error_description"] ?? params["error"] {
      throw AuthError.implicitGrantRedirect(message: errorMessage)
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

    let user = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("user"),
        method: .get,
        headers: [.authorization: "\(tokenType) \(accessToken)"]
      )
    ).decoded(as: User.self, decoder: configuration.resolvedDecoder)

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
        message: params["error_description"]
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
  @available(*, deprecated, message: "Use importSession(accessToken:refreshToken:) instead.")
  @discardableResult
  public func setSession(accessToken: String, refreshToken: String) async throws -> Session {
    try await importSession(accessToken: accessToken, refreshToken: refreshToken)
  }

  /// Signs in with tokens from another place, such as a web page, another device, or a server.
  ///
  /// When the access token is expired, or its `exp` claim cannot be read, the client refreshes
  /// the session with `refreshToken`, which emits ``AuthChangeEvent/tokenRefreshed``. Otherwise
  /// it fetches the user of `accessToken`. In both cases it then emits
  /// ``AuthChangeEvent/signedIn``.
  ///
  /// - Parameters:
  ///   - accessToken: The access token of the session.
  ///   - refreshToken: The refresh token of the session.
  /// - Returns: The stored session.
  @discardableResult
  public func importSession(accessToken: String, refreshToken: String) async throws -> Session {
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
      session = try await sessionManager.refreshSession(refreshToken)
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
          headers: [.authorization: "Bearer \(accessToken)"]
        )
      )
    } catch let AuthError.api(_, _, _, response)
      where [404, 403, 401].contains(response.statusCode)
    {
      // ignore 404s since user might not exist anymore
      // ignore 401s, and 403s since an invalid or expired JWT should sign out the current session.
    }
  }

  /// Log in an user given a User supplied OTP received via email.
  @discardableResult
  @available(
    *, deprecated,
    message: "Use verifyOTP(email:token:type:) with a VerifyOTPResult result instead."
  )
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
          (redirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
          VerifyOTPParams.email(
            VerifyEmailOTPParams(
              email: email,
              token: token,
              type: type,
              gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
            )
          )
        )
      )
    )
  }

  /// Log in an user given a User supplied OTP received via mobile.
  @discardableResult
  @available(
    *, deprecated, message: "Use verifyOTP(phone:token:type:) with a Session result instead."
  )
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
        body: configuration.resolvedEncoder.encode(
          VerifyOTPParams.mobile(
            VerifyMobileOTPParams(
              phone: phone,
              token: token,
              type: type,
              gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
            )
          )
        )
      )
    )
  }

  /// Log in an user given a token hash received via email.
  @discardableResult
  public func verifyOTP(
    tokenHash: String,
    type: EmailOTPType
  ) async throws -> AuthResponse {
    try await _verifyOTP(
      request: .init(
        url: configuration.url.appendingPathComponent("verify"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          VerifyOTPParams.tokenHash(
            VerifyTokenHashParams(tokenHash: tokenHash, type: type)
          )
        )
      )
    )
  }

  /// Signs in with a one-time code that the user received by email.
  ///
  /// The deprecated overload that returns ``AuthResponse`` has the same labels. Give the result
  /// the type ``VerifyOTPResult`` to select this one:
  ///
  /// ```swift
  /// let result: VerifyOTPResult = try await client.auth.verifyOTP(
  ///   email: email, token: code, type: .email)
  /// ```
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - token: The code from the email.
  ///   - type: The kind of code.
  /// - Returns: The session, or the message of the first confirmation of a secure email change.
  @_disfavoredOverload
  @discardableResult
  public func verifyOTP(
    email: String,
    token: String,
    type: EmailOTPType
  ) async throws -> VerifyOTPResult {
    let result = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("verify"),
        method: .post,
        query: [
          configuration.redirectTo.map {
            URLQueryItem(name: "redirect_to", value: $0.absoluteString)
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
          VerifyOTPParams.email(
            VerifyEmailOTPParams(email: email, token: token, type: type, gotrueMetaSecurity: nil)
          )
        )
      )
    )
    .decoded(as: VerifyOTPBody.self, decoder: configuration.resolvedDecoder)
    .result

    if case .signedIn(let session) = result {
      await sessionManager.update(session)
      eventEmitter.emit(.signedIn, session: session)
    }
    return result
  }

  /// Signs in with a one-time code that the user received by SMS or WhatsApp.
  ///
  /// The deprecated overload that returns ``AuthResponse`` has the same labels. Give the result
  /// the type ``Session`` to select this one:
  ///
  /// ```swift
  /// let session: Session = try await client.auth.verifyOTP(
  ///   phone: phone, token: code, type: .sms)
  /// ```
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the country code.
  ///   - token: The code from the message.
  ///   - type: The kind of code.
  /// - Returns: The new session.
  @_disfavoredOverload
  @discardableResult
  public func verifyOTP(
    phone: String,
    token: String,
    type: PhoneOTPType
  ) async throws -> Session {
    let session = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("verify"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          VerifyOTPParams.mobile(
            VerifyMobileOTPParams(phone: phone, token: token, type: type, gotrueMetaSecurity: nil)
          )
        )
      )
    )
    .decoded(as: Session.self, decoder: configuration.resolvedDecoder)

    await sessionManager.update(session)
    eventEmitter.emit(.signedIn, session: session)
    return session
  }

  private func _verifyOTP(request: HTTPRequest) async throws -> AuthResponse {
    let response = try await api.execute(request).decoded(
      as: AuthResponse.self,
      decoder: configuration.resolvedDecoder
    )

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
  @available(*, deprecated, message: "Use resend(email:type:options:) instead.")
  @_disfavoredOverload
  public func resend(
    email: String,
    type: ResendEmailType,
    emailRedirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await _resend(
      email: email, type: type, emailRedirectTo: emailRedirectTo, captchaToken: captchaToken)
  }

  /// Sends a sign-up confirmation or an email change email again.
  ///
  /// - Parameters:
  ///   - email: The user's email address.
  ///   - type: The kind of email to send again.
  ///   - options: The redirect URL and the captcha token.
  public func resend(
    email: String,
    type: ResendEmailType,
    options: ResendEmailOptions = .init()
  ) async throws {
    try await _resend(
      email: email, type: type, emailRedirectTo: options.redirectTo,
      captchaToken: options.captchaToken)
  }

  private func _resend(
    email: String,
    type: ResendEmailType,
    emailRedirectTo: URL?,
    captchaToken: String?
  ) async throws {
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("resend"),
        method: .post,
        query: [
          (emailRedirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
          ResendEmailParams(
            type: type,
            email: email,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:)),
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod
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
  @available(*, deprecated, message: "Use resend(phone:type:options:) instead.")
  public func resend(
    phone: String,
    type: ResendMobileType,
    captchaToken: String? = nil
  ) async throws -> ResendMobileResponse {
    ResendMobileResponse(
      messageId: try await _resend(phone: phone, type: type, captchaToken: captchaToken)?.rawValue)
  }

  /// Sends a phone confirmation code again.
  ///
  /// A call with no `options` argument and no result type selects the deprecated overload that
  /// returns ``ResendMobileResponse``. Pass `options`, or give the result the type `MessageID?`.
  ///
  /// - Parameters:
  ///   - phone: The user's phone number, with the country code.
  ///   - type: The kind of code to send again.
  ///   - options: The captcha token.
  /// - Returns: The ID that the SMS provider gave the message, when the server sends one.
  @_disfavoredOverload
  @discardableResult
  public func resend(
    phone: String,
    type: ResendPhoneType,
    options: ResendPhoneOptions = .init()
  ) async throws -> MessageID? {
    try await _resend(phone: phone, type: type, captchaToken: options.captchaToken)
  }

  private func _resend(
    phone: String,
    type: ResendMobileType,
    captchaToken: String?
  ) async throws -> MessageID? {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("resend"),
        method: .post,
        body: configuration.resolvedEncoder.encode(
          ResendMobileParams(
            type: type,
            phone: phone,
            gotrueMetaSecurity: captchaToken.map(AuthMetaSecurity.init(captchaToken:))
          )
        )
      )
    )
    .decoded(as: MessageIDBody.self, decoder: configuration.resolvedDecoder)
    .messageId
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

  /// Gets the current user details if there is an existing session.
  /// - Parameter jwt: Takes in an optional access token jwt. If no jwt is provided, user() will
  /// attempt to get the jwt from the current session.
  ///
  /// Should be used only when you require the most current user data. For faster results, ``currentUser`` is recommended.
  @available(*, deprecated, message: "Use user() or user(jwt:) instead.")
  public func user(jwt: String? = nil) async throws -> User {
    if let jwt {
      return try await user(jwt: jwt)
    }
    return try await user()
  }

  /// Fetches the user of the current session from the Auth server.
  ///
  /// The session is refreshed first when it is expired. For the user stored with the session,
  /// with no request, read ``currentUser``.
  ///
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or the error of the
  ///   refresh or of the request.
  public func user() async throws -> User {
    let request = HTTPRequest(url: configuration.url.appendingPathComponent("user"), method: .get)
    return try await api.authorizedExecute(request).decoded(decoder: configuration.resolvedDecoder)
  }

  /// Fetches the user that an access token belongs to from the Auth server.
  ///
  /// The stored session is not read and not changed.
  ///
  /// - Parameter jwt: The access token to send.
  /// - Throws: The error of the request, for example when the Auth server rejects `jwt`.
  public func user(jwt: String) async throws -> User {
    var request = HTTPRequest(url: configuration.url.appendingPathComponent("user"), method: .get)
    request.headers[.authorization] = "Bearer \(jwt)"
    return try await api.execute(request).decoded(decoder: configuration.resolvedDecoder)
  }

  /// Updates user data, if there is a logged in user.
  @available(*, deprecated, message: "Use updateUser(_:redirectTo:) instead.")
  @discardableResult
  public func update(user: UserAttributes, redirectTo: URL? = nil) async throws -> User {
    var user = user

    if user.email != nil {
      let (codeChallenge, codeChallengeMethod) = prepareForPKCE()
      user.codeChallenge = codeChallenge
      user.codeChallengeMethod = codeChallengeMethod
    }

    return try await _updateUser(body: user, redirectTo: redirectTo)
  }

  /// Updates the current user.
  ///
  /// The stored session gets the updated user, and the client emits
  /// ``AuthChangeEvent/userUpdated``.
  ///
  /// - Parameters:
  ///   - changes: The changes to make.
  ///   - redirectTo: The URL the confirmation link of an email change redirects to. When `nil`,
  ///     the client uses ``Configuration/redirectTo``.
  /// - Returns: The updated user.
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or the error of the
  ///   refresh or of the request.
  @discardableResult
  public func updateUser(_ changes: UpdateUser, redirectTo: URL? = nil) async throws -> User {
    var changes = changes

    if changes.email != nil {
      let (codeChallenge, codeChallengeMethod) = prepareForPKCE()
      changes.codeChallenge = codeChallenge
      changes.codeChallengeMethod = codeChallengeMethod
    }

    return try await _updateUser(body: changes, redirectTo: redirectTo)
  }

  private func _updateUser(body: some Encodable, redirectTo: URL?) async throws -> User {
    var session = try await sessionManager.session()
    let updatedUser = try await api.authorizedExecute(
      .init(
        url: configuration.url.appendingPathComponent("user"),
        method: .put,
        query: [
          (redirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(body)
      )
    ).decoded(as: User.self, decoder: configuration.resolvedDecoder)
    session.user = updatedUser
    await sessionManager.update(session)
    eventEmitter.emit(.userUpdated, session: session)
    return updatedUser
  }

  /// Gets all the identities linked to a user.
  @available(*, deprecated, message: "Use identities() instead.")
  public func userIdentities() async throws -> [UserIdentity] {
    try await identities()
  }

  /// Fetches the identities linked to the current user from the Auth server.
  ///
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or the error of the
  ///   refresh or of the request.
  public func identities() async throws -> [UserIdentity] {
    try await user().identities ?? []
  }

  /// Link an identity to the current user using an ID token.
  @available(*, deprecated, message: "Use linkIdentity(idToken:) instead.")
  @discardableResult
  public func linkIdentityWithIdToken(
    credentials: OpenIDConnectCredentials
  ) async throws -> Session {
    var credentials = credentials
    credentials.linkIdentity = true
    return try await _linkIdentity(idTokenBody: credentials)
  }

  /// Links an identity to the current user with an ID token that a third-party identity provider
  /// issued.
  ///
  /// The stored session is replaced, and the client emits ``AuthChangeEvent/userUpdated``.
  ///
  /// - Parameter credentials: The ID token and the values the server needs to check it.
  /// - Returns: The new session.
  @discardableResult
  public func linkIdentity(idToken credentials: IDTokenCredentials) async throws -> Session {
    try await _linkIdentity(idTokenBody: IDTokenGrantBody(credentials, linkIdentity: true))
  }

  private func _linkIdentity(idTokenBody: some Encodable) async throws -> Session {
    let accessToken = try await sessionManager.session().accessToken
    let session = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("token"),
        method: .post,
        query: [URLQueryItem(name: "grant_type", value: "id_token")],
        headers: [.authorization: "Bearer \(accessToken)"],
        body: configuration.resolvedEncoder.encode(idTokenBody)
      )
    ).decoded(as: Session.self, decoder: configuration.resolvedDecoder)

    await sessionManager.update(session)
    eventEmitter.emit(.userUpdated, session: session)

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
  ) async throws {
    try await linkIdentity(
      provider: provider,
      scopes: scopes,
      redirectTo: redirectTo,
      queryParams: queryParams,
      launchURL: { Dependencies[clientID].urlOpener.open($0) }
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
    .decoded(as: Response.self, decoder: configuration.resolvedDecoder)

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
  @available(*, deprecated, message: "Use resetPassword(email:options:) instead.")
  public func resetPasswordForEmail(
    _ email: String,
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) async throws {
    try await resetPassword(
      email: email,
      options: ResetPasswordOptions(redirectTo: redirectTo, captchaToken: captchaToken)
    )
  }

  /// Sends a password reset email.
  ///
  /// - Parameters:
  ///   - email: The email address of the user.
  ///   - options: The redirect URL and the captcha token.
  public func resetPassword(
    email: String,
    options: ResetPasswordOptions = .init()
  ) async throws {
    let redirectTo = options.redirectTo
    let captchaToken = options.captchaToken
    let (codeChallenge, codeChallengeMethod) = prepareForPKCE()

    _ = try await api.execute(
      .init(
        url: configuration.url.appendingPathComponent("recover"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectTo).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: configuration.resolvedEncoder.encode(
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
  @available(
    *, deprecated,
    message:
      "Use refreshSession() to refresh the stored session. A refresh token from another place has no exact replacement: importSession(accessToken:refreshToken:) also needs an access token and emits signedIn."
  )
  @discardableResult
  public func refreshSession(refreshToken: String? = nil) async throws -> Session {
    guard let refreshToken = refreshToken ?? currentSession?.refreshToken else {
      throw AuthError.sessionMissing
    }

    return try await sessionManager.refreshSession(refreshToken)
  }

  /// Refreshes the stored session and returns the new one, whether or not it is expired.
  ///
  /// - Returns: The new session.
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or the error of the
  ///   refresh.
  @discardableResult
  public func refreshSession() async throws -> Session {
    guard let refreshToken = currentSession?.refreshToken else {
      throw AuthError.sessionMissing
    }

    return try await sessionManager.refreshSession(refreshToken)
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
    if configuration.emitLocalSessionAsInitialSession {
      guard let currentSession else {
        eventEmitter.emit(.initialSession, session: nil, token: token)
        return
      }

      eventEmitter.emit(.initialSession, session: currentSession, token: token)

      Task {
        if currentSession.isExpired() {
          _ = try? await sessionManager.refreshSession(currentSession.refreshToken)
          // No need to emit `tokenRefreshed` nor `signOut` event since the `refreshSession` does it already.
        }
      }
    } else {
      let session = try? await sessionManager.session()
      eventEmitter.emit(.initialSession, session: session, token: token)

      // Properly expecting issues during tests isn't working as expected, I think because the reportIssue is usually triggered inside an unstructured Task
      // because of this I'm disabling issue reporting during tests, so we can use it only for advising developers when running their applications.
      if !isTesting {
        reportIssue(
          """
          Initial session emitted after attempting to refresh the local stored session.
          This is incorrect behavior and will be fixed in the next major release since it's a breaking change.
          To opt-in to the new behavior now, set `emitLocalSessionAsInitialSession: true` in your AuthClient configuration.
          The new behavior ensures that the locally stored session is always emitted, regardless of its validity or expiration.
          If you rely on the initial session to opt users in, you need to add an additional check for `session.isExpired` in the session.

          Check https://github.com/supabase/supabase-swift/pull/822 for more information.
          """
        )
      }
    }
  }

  nonisolated private func prepareForPKCE() -> (
    codeChallenge: String?, codeChallengeMethod: String?
  ) {
    guard configuration.flowType == .pkce else {
      return (nil, nil)
    }

    let codeVerifier = pkce.generateCodeVerifier()
    codeVerifierStorage.set(codeVerifier)

    let codeChallenge = pkce.generateCodeChallenge(codeVerifier)
    let codeChallengeMethod = codeVerifier == codeChallenge ? "plain" : "s256"

    return (codeChallenge, codeChallengeMethod)
  }

  private func isImplicitGrantFlow(params: [String: String]) -> Bool {
    params["access_token"] != nil || params["error_description"] != nil || params["error"] != nil
  }

  private func isPKCEFlow(params: [String: String]) -> Bool {
    let currentCodeVerifier = codeVerifierStorage.get()
    return params["code"] != nil || params["error_description"] != nil || params["error"] != nil
      || params["error_code"] != nil && currentCodeVerifier != nil
  }

  nonisolated private func getURLForProvider(
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

    if let redirectTo = redirectTo ?? configuration.redirectTo {
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

  /// Fetches a JWK from the JWKS endpoint with caching
  /// Returns nil if the key is not found, allowing graceful fallback to server-side verification
  private func fetchJWK(kid: String, jwks: JWKS? = nil) async throws -> JWK? {
    // Try fetching from the supplied jwks
    if let jwk = jwks?.keys.first(where: { $0.kid == kid }) {
      return jwk
    }

    let now = date()
    let storageKey = configuration.storageKey ?? defaultStorageKey

    // Try fetching from global cache
    if let cached = await globalJWKSCache.get(for: storageKey),
      let jwk = cached.jwks.keys.first(where: { $0.kid == kid })
    {
      // Check if cache is still valid (not stale)
      if cached.cachedAt.addingTimeInterval(JWKS_TTL) > now {
        return jwk
      }
    }

    // Fetch from well-known endpoint
    let response = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent(".well-known/jwks.json"),
        method: .get
      )
    )

    let fetchedJWKS = try response.decoded(as: JWKS.self, decoder: configuration.resolvedDecoder)

    // Return nil if JWKS is empty (will fallback to getUser)
    guard !fetchedJWKS.keys.isEmpty else {
      return nil
    }

    // Cache the JWKS globally
    await globalJWKSCache.set(
      CachedJWKS(jwks: fetchedJWKS, cachedAt: now),
      for: storageKey
    )

    // Find the signing key - return nil if not found (will fallback to getUser)
    // This handles key rotation scenarios where the JWT is signed with a key not yet in the cache
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
  /// - Throws: `AuthError.jwtVerificationFailed` if verification fails, or `AuthError.sessionMissing` if no session exists.
  @available(
    *, deprecated, message: "Use claims(options:) or claims(jwt:options:) instead."
  )
  public func getClaims(
    jwt: String? = nil,
    options: GetClaimsOptions = GetClaimsOptions()
  ) async throws -> JWTClaimsResponse {
    let decodedJWT = try await verifiedJWT(
      jwt, allowsExpired: options.allowExpired, jwks: options.jwks)

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

  /// Verifies the access token of the current session and returns its claims.
  ///
  /// The client verifies a token signed with an asymmetric key (ECC or RSA) on the device, with
  /// the key set of the Auth server, which it caches. For any other token it asks the Auth server,
  /// as ``user(jwt:)`` does.
  ///
  /// - Parameter options: Options for the verification.
  /// - Returns: The verified claims, with the header and the signature of the token.
  /// - Throws: ``AuthError/sessionMissing`` when no session is stored, or
  ///   ``AuthError/jwtVerificationFailed(message:)`` when the token is malformed, expired, has a
  ///   bad signature, or has no `sub` or `exp` claim.
  public func claims(options: ClaimsOptions = ClaimsOptions()) async throws -> VerifiedClaims {
    try VerifiedClaims(
      await verifiedJWT(nil, allowsExpired: options.allowsExpired, jwks: options.jwks))
  }

  /// Verifies a JSON Web Token and returns its claims.
  ///
  /// The client verifies a token signed with an asymmetric key (ECC or RSA) on the device, with
  /// the key set of the Auth server, which it caches. For any other token it asks the Auth server,
  /// as ``user(jwt:)`` does.
  ///
  /// - Parameters:
  ///   - jwt: The token to verify.
  ///   - options: Options for the verification.
  /// - Returns: The verified claims, with the header and the signature of the token.
  /// - Throws: ``AuthError/jwtVerificationFailed(message:)`` when the token is malformed, expired,
  ///   has a bad signature, or has no `sub` or `exp` claim.
  public func claims(
    jwt: String,
    options: ClaimsOptions = ClaimsOptions()
  ) async throws -> VerifiedClaims {
    try VerifiedClaims(
      await verifiedJWT(jwt, allowsExpired: options.allowsExpired, jwks: options.jwks))
  }

  private func verifiedJWT(
    _ jwt: String?,
    allowsExpired: Bool,
    jwks: JWKS?
  ) async throws -> DecodedJWT {
    let token: String
    if let jwt {
      token = jwt
    } else {
      guard let session = try? await sessionManager.session() else {
        throw AuthError.sessionMissing
      }
      token = session.accessToken
    }

    guard let decodedJWT = JWT.decode(token) else {
      throw AuthError.jwtVerificationFailed(message: "Invalid JWT structure")
    }

    if !allowsExpired {
      if let exp = decodedJWT.payload["exp"] as? TimeInterval {
        let now = date().timeIntervalSince1970
        if exp <= now {
          throw AuthError.jwtVerificationFailed(message: "JWT has expired")
        }
      }
    }

    let alg = decodedJWT.header["alg"] as? String
    let kid = decodedJWT.header["kid"] as? String

    // Try to fetch the signing key for asymmetric JWTs
    // Returns nil if: no alg, symmetric algorithm (HS256/HS512), no kid, or key not found in JWKS
    let signingKey: JWK?
    if let alg, !alg.hasPrefix("HS"), let kid {
      // Only attempt to fetch JWK for asymmetric algorithms with a kid
      signingKey = try await fetchJWK(kid: kid, jwks: jwks)
    } else {
      signingKey = nil
    }

    // If no signing key available (symmetric algorithm, RS256, no kid, or key not found),
    // fallback to server-side verification via getUser()
    guard
      let signingKey,
      let alg = signingKey.alg,
      let algorithm = JWTAlgorithm(rawValue: alg)
    else {
      _ = try await user(jwt: token)
      // getUser succeeds, so claims can be trusted
      return decodedJWT
    }

    guard algorithm.verify(jwt: decodedJWT, jwk: signingKey) else {
      throw AuthError.jwtVerificationFailed(message: "Invalid JWT signature")
    }

    return decodedJWT
  }
}

extension AuthClient {
  /// Notification posted when an auth state event is triggered.
  @available(*, deprecated, message: "Use events() instead.")
  public static let didChangeAuthStateNotification = _didChangeAuthStateNotification

  /// A user info key to retrieve the ``AuthChangeEvent`` value for a
  /// ``AuthClient/didChangeAuthStateNotification`` notification.
  @available(*, deprecated, message: "Use events() instead.")
  public static let authChangeEventInfoKey = _authChangeEventInfoKey

  /// A user info key to retrieve the ``Session`` value for a
  /// ``AuthClient/didChangeAuthStateNotification`` notification.
  @available(*, deprecated, message: "Use events() instead.")
  public static let authChangeSessionInfoKey = _authChangeSessionInfoKey

  static let _didChangeAuthStateNotification = Notification.Name(
    "AuthClient.didChangeAuthStateNotification"
  )
  static let _authChangeEventInfoKey = "AuthClient.authChangeEvent"
  static let _authChangeSessionInfoKey = "AuthClient.authChangeSession"
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
