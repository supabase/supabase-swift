import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

/// One project's world: a server behind a `RecordingTransport`, a `SignalingTestClock` that drives
/// both auto refresh and the injected `now`, and a storage key no other test uses.
struct Race: Sendable {
  static let lifetime: TimeInterval = 3600
  private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

  let clock = SignalingTestClock()
  let transport = RecordingTransport()
  let localStorage = InMemoryLocalStorage()
  let storageKey = uniqueStorageKey()
  private let start: SignalingTestClock.Instant
  private let skew: TimeInterval

  /// - Parameter skew: How far the device clock runs ahead of the server's.
  init(skew: TimeInterval = 0) {
    start = clock.now
    self.skew = skew
  }

  var now: @Sendable () -> Date {
    { [clock, start, skew] in
      Self.epoch.addingTimeInterval(skew + start.duration(to: clock.now).timeInterval)
    }
  }

  private var elapsed: TimeInterval {
    start.duration(to: clock.now).timeInterval
  }

  func makeClient(
    autoRefresh: AuthClient.AutoRefreshPolicy = .manual,
    storage: (any AuthLocalStorage)? = nil,
    beforeRefreshingHeldSession: @escaping @Sendable () async -> Void = {}
  ) -> AuthClient {
    makeClient(
      url: clientURL, autoRefresh: autoRefresh, storage: storage ?? localStorage,
      beforeRefreshingHeldSession: beforeRefreshingHeldSession)
  }

  /// A new client on the same storage, so it reads what the race left on disk, as the next launch
  /// would.
  func relaunch() -> AuthClient {
    makeClient(url: clientURL, autoRefresh: .manual, storage: localStorage)
  }

  private func makeClient(
    url: URL,
    autoRefresh: AuthClient.AutoRefreshPolicy,
    storage: any AuthLocalStorage,
    beforeRefreshingHeldSession: @escaping @Sendable () async -> Void = {}
  ) -> AuthClient {
    var platform = AuthPlatform.live
    platform.lifecycleEvents = { AsyncStream { $0.finish() } }
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        localStorage: storage,
        http: HTTPClientConfiguration(transport: transport),
        autoRefresh: autoRefresh,
        observesAppLifecycle: false,
        clock: clock
      ),
      date: now,
      pkce: .live,
      platform: platform,
      beforeRefreshingHeldSession: beforeRefreshingHeldSession
    )
  }

  /// A session the server issues now, named by its access token `<name>-access` and its refresh
  /// token `<name>-refresh`. Its `expiresAt` is on the server clock, which the device clock is
  /// `skew` ahead of.
  func issue(_ name: String, lifetime: TimeInterval = Self.lifetime) -> Session {
    Session(
      accessToken: "\(name)-access",
      tokenType: "bearer",
      expiresIn: lifetime,
      expiresAt: Self.epoch.addingTimeInterval(elapsed + lifetime).timeIntervalSince1970,
      refreshToken: "\(name)-refresh",
      user: User(fromMockNamed: "user")
    )
  }

  static func user(nickname: String) -> User {
    var user = User(fromMockNamed: "user")
    user.userMetadata["nickname"] = .string(nickname)
    return user
  }

  func advance(to elapsed: TimeInterval, grace: Duration = .seconds(1)) async {
    await clock.advance(by: .seconds(elapsed - self.elapsed), grace: grace)
  }

  /// Waits until auto refresh sleeps toward its deadline, so that advancing the clock fires it.
  func waitForTheScheduledRefresh() async {
    let isScheduled = await waitUntil { [clock] in clock.pendingSleepCount > 0 }
    #expect(isScheduled)
  }

  var refreshRequestCount: Int {
    requestCount(grantType: "refresh_token")
  }

  func requestCount(grantType: String) -> Int {
    transport.requests.filter { Self.isToken($0.head, grantType: grantType) }.count
  }

  /// Answers a password sign-in with the session `session` returns for the request body.
  func answerSignIn(
    through gate: Gate? = nil, _ session: @escaping @Sendable (_ body: String) -> Session
  ) {
    answerToken("password", through: gate) { try Self.ok(session($0)) }
  }

  func answerRefresh(
    through gate: Gate? = nil, _ response: @escaping @Sendable () throws -> (HTTPResponse, Data)
  ) {
    answerToken("refresh_token", through: gate) { _ in try response() }
  }

  func answerCodeExchange(
    through gate: Gate? = nil, _ response: @escaping @Sendable () throws -> (HTTPResponse, Data)
  ) {
    answerToken("pkce", through: gate) { _ in try response() }
  }

  func answerSignOut() {
    transport.respond(when: { $0.url?.path.hasSuffix("/logout") == true }) { _, _ in
      (HTTPResponse(status: .noContent), Data())
    }
  }

  func answerUserUpdate(with user: User) {
    transport.respond(when: { $0.method == .put && $0.url?.path.hasSuffix("/user") == true }) {
      _, _ in try Self.ok(user)
    }
  }

  func answerUser(_ user: User) {
    transport.respond(when: { $0.method == .get && $0.url?.path.hasSuffix("/user") == true }) {
      _, _ in try Self.ok(user)
    }
  }

  /// Answers `GET /user/identities/authorize` with `url`, as the server does for
  /// `skip_http_redirect=true`.
  func answerIdentityAuthorize(url: URL) {
    transport.respond(when: {
      $0.method == .get && $0.url?.path.hasSuffix("/user/identities/authorize") == true
    }) { _, _ in try Self.ok(["url": url]) }
  }

  private func answerToken(
    _ grantType: String,
    through gate: Gate?,
    _ response: @escaping @Sendable (_ body: String) throws -> (HTTPResponse, Data)
  ) {
    transport.respond(when: { Self.isToken($0, grantType: grantType) }) { _, body in
      await gate?.pass()
      return try response(String(decoding: body ?? Data(), as: UTF8.self))
    }
  }

  private static func isToken(_ request: HTTPTypes.HTTPRequest, grantType: String) -> Bool {
    request.url?.path.hasSuffix("/token") == true
      && request.url?.query?.contains("grant_type=\(grantType)") == true
  }

  static func ok(_ value: some Encodable) throws -> (HTTPResponse, Data) {
    (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(value))
  }

  static func error(
    _ status: HTTPResponse.Status, code: String, message: String
  ) -> (HTTPResponse, Data) {
    (
      HTTPResponse(status: status, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
      Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    )
  }
}
