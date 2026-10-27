import Foundation
import IssueReporting

actor AutoRefreshController {
  private struct State {
    var isRequested: Bool
    var isInForeground: Bool

    var shouldRun: Bool { isRequested && isInForeground }
  }

  private let policy: AuthClient.AutoRefreshPolicy
  private let owner = UUID()
  private let store: SessionStore
  private let driver: Refresher.Driver
  private var state: State
  private var lastApply: Task<Void, Never>?

  init(
    policy: AuthClient.AutoRefreshPolicy,
    observesAppLifecycle: Bool,
    store: SessionStore,
    driver: Refresher.Driver
  ) {
    self.policy = policy
    self.store = store
    self.driver = driver
    state = State(isRequested: policy == .automatic, isInForeground: !observesAppLifecycle)
  }

  var isRegistered: Bool {
    get async {
      await lastApply?.value
      return await store.isAutoRefreshStarted(by: owner)
    }
  }

  func start() async {
    guard policy == .automatic else {
      reportIssue(
        "startAutoRefresh() has no effect: autoRefresh is \(policy), not .automatic.")
      return
    }
    state.isRequested = true
    await apply()
  }

  func stop() async {
    state.isRequested = false
    await apply()
  }

  func handle(_ event: AppLifecycleEvent) async {
    switch event {
    case .foreground: state.isInForeground = true
    case .background: state.isInForeground = false
    case .protectedDataDidBecomeAvailable: return
    }
    await apply()
  }

  /// Waits for the previous apply, then sends the state as it is when this one runs, so the store
  /// ends with the state of the last call.
  func apply() async {
    let previous = lastApply
    let current = Task {
      await previous?.value
      if state.shouldRun {
        await store.startAutoRefresh(for: owner, using: driver)
      } else {
        await store.stopAutoRefresh(for: owner)
      }
    }
    lastApply = current
    await current.value
  }
}
