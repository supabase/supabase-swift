import ConcurrencyExtras
import Foundation
import Helpers
import Logging

final class TokenBox: Sendable {
  /// The server closes every channel the moment the token expires.
  static let refreshLeeway: Duration = .seconds(60)
  static let refreshInterval: Duration = .seconds(10)
  static let maximumRefreshDelay: Duration = .seconds(365 * 24 * 60 * 60)

  struct Mark: Sendable {
    fileprivate let calls: Int
  }

  private struct State {
    var token: String?
    var expiresAt: Date?
    var generation = 0
    var calls = 0
    var lastCallStart: Duration?
    var call: Call?
    var abandonedCall: Int?
    var refreshTimer: Task<Void, Never>?
  }

  private struct Call {
    let number: Int
    let generation: Int
    var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    var tasks: [Task<Void, Never>] = []
  }

  private enum Step {
    case done
    case wait(call: Int, thenAgain: Bool)
    case start(call: Int)
  }

  private let provider: (@Sendable () async throws -> String?)?
  private let callTimeout: Duration
  private let clock: any Clock<Duration>
  private let elapsed: @Sendable () -> Duration
  private let now: @Sendable () -> Date
  private let logger: Logger
  private let state: LockIsolated<State>
  private let pushSink: AsyncStream<Void>.Continuation
  private let refreshDueSink: AsyncStream<Void>.Continuation

  let pushRequests: AsyncStream<Void>
  let refreshesDue: AsyncStream<Void>

  init(
    token: String?,
    provider: (@Sendable () async throws -> String?)?,
    callTimeout: Duration,
    clock: any Clock<Duration>,
    logger: Logger
  ) {
    self.provider = provider
    self.callTimeout = callTimeout
    self.clock = clock
    self.logger = logger
    let elapsed = Self.elapsedTime(on: clock)
    let start = Date()
    self.elapsed = elapsed
    now = { start.addingTimeInterval(elapsed().timeInterval) }
    state = LockIsolated(State(token: token, expiresAt: Self.expiry(of: token)))
    (pushRequests, pushSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    (refreshesDue, refreshDueSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  deinit {
    state.value.refreshTimer?.cancel()
    pushSink.finish()
    refreshDueSink.finish()
  }

  var token: String? {
    state.value.token
  }

  func store(_ token: String) {
    let isChanged = state.withValue { state in
      guard token != state.token else { return false }
      state.generation += 1
      state.token = token
      state.expiresAt = Self.expiry(of: token)
      armRefreshTimer(&state)
      return true
    }
    if isChanged { pushSink.yield() }
  }

  func requestPush() {
    pushSink.yield()
  }

  func mark() -> Mark {
    Mark(calls: state.value.calls)
  }

  func refreshUnlessRecent() async {
    await awaitCall(startedAfter: nil)
  }

  func refresh(startedAfter mark: Mark) async {
    await awaitCall(startedAfter: mark)
  }

  private func awaitCall(startedAfter mark: Mark?) async {
    guard provider != nil else { return }
    while !Task.isCancelled {
      switch nextStep(after: mark) {
      case .done:
        return
      case .wait(let call, let thenAgain):
        await waitForCall(call)
        if !thenAgain { return }
      case .start(let call):
        startCall(call)
        await waitForCall(call)
        return
      }
    }
  }

  private func nextStep(after mark: Mark?) -> Step {
    state.withValue { state in
      if let call = state.call {
        let startedBefore = mark.map { call.number <= $0.calls } ?? false
        return .wait(call: call.number, thenAgain: startedBefore)
      }
      if state.abandonedCall != nil { return .done }
      if let mark {
        if state.calls > mark.calls { return .done }
      } else if let last = state.lastCallStart, elapsed() - last < Self.refreshInterval {
        return .done
      }
      state.calls += 1
      state.lastCallStart = elapsed()
      state.call = Call(number: state.calls, generation: state.generation)
      return .start(call: state.calls)
    }
  }

  private func startCall(_ number: Int) {
    guard let provider else { return }
    // A local opens the existential; passing `self.clock` fails with "cannot conform to Clock".
    let clock = clock
    let sleep = Self.sleeperUntilDeadline(on: clock, after: callTimeout)
    let timeout = callTimeout
    let logger = logger
    let timer = Task { [weak self] in
      do {
        try await sleep()
      } catch {
        return
      }
      logger.error("The access token callback did not return within \(timeout).")
      self?.finishCall(number, token: nil, isTimeout: true)
    }
    let call = Task { [weak self] in
      let token: String?
      do {
        token = try await provider()
      } catch {
        logger.error("Failed to fetch access token: \(error)")
        token = nil
      }
      self?.finishCall(number, token: token, isTimeout: false)
    }
    let isRunning = state.withValue { state in
      guard state.call?.number == number else { return false }
      state.call?.tasks = [timer, call]
      return true
    }
    if !isRunning {
      timer.cancel()
    }
  }

  private func finishCall(_ number: Int, token: String?, isTimeout: Bool) {
    let finished: (call: Call, isChanged: Bool)? = state.withValue { state in
      if !isTimeout, state.abandonedCall == number { state.abandonedCall = nil }
      guard let call = state.call, call.number == number else { return nil }
      state.call = nil
      if isTimeout { state.abandonedCall = number }
      var isChanged = false
      if let token, call.generation == state.generation, token != state.token {
        state.token = token
        state.expiresAt = Self.expiry(of: token)
        isChanged = true
      }
      armRefreshTimer(&state)
      return (call, isChanged)
    }
    guard let finished else { return }
    for task in finished.call.tasks {
      task.cancel()
    }
    for waiter in finished.call.waiters.values {
      waiter.resume()
    }
    if finished.isChanged { pushSink.yield() }
  }

  private func waitForCall(_ number: Int) async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let isWaiting = state.withValue { state in
          guard state.call?.number == number, !Task.isCancelled else { return false }
          state.call?.waiters[id] = continuation
          return true
        }
        if !isWaiting { continuation.resume() }
      }
    } onCancel: {
      state.withValue { $0.call?.waiters.removeValue(forKey: id) }?.resume()
    }
  }

  private func armRefreshTimer(_ state: inout State) {
    state.refreshTimer?.cancel()
    state.refreshTimer = nil
    guard provider != nil, let expiresAt = state.expiresAt else { return }
    // Clamped before the conversion: `Int(_:)` traps on a value out of range, and `exp` is
    // whatever number the token carries.
    let remaining = min(
      max(expiresAt.timeIntervalSince(now()).rounded(), 0), Self.maximumRefreshDelay.timeInterval)
    let delay = max(.seconds(Int(remaining)) - Self.refreshLeeway, Self.refreshInterval)
    // A local opens the existential; passing `self.clock` fails with "cannot conform to Clock".
    let clock = clock
    let sleep = Self.sleeperUntilDeadline(on: clock, after: delay)
    let sink = refreshDueSink
    state.refreshTimer = Task {
      do {
        try await sleep()
      } catch {
        return
      }
      sink.yield()
    }
  }

  private static func expiry(of token: String?) -> Date? {
    guard let token, let exp = JWT.decodePayload(token)?["exp"] as? TimeInterval else {
      return nil
    }
    return Date(timeIntervalSince1970: exp)
  }

  private static func elapsedTime(on clock: some Clock<Duration>) -> @Sendable () -> Duration {
    let start = clock.now
    return { start.duration(to: clock.now) }
  }

  private static func sleeperUntilDeadline(
    on clock: some Clock<Duration>, after delay: Duration
  ) -> @Sendable () async throws -> Void {
    let deadline = clock.now.advanced(by: delay)
    return { try await clock.sleep(until: deadline, tolerance: nil) }
  }
}
