//
//  AppLifecycleTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 06/11/26.
//

import Foundation
import TestHelpers
import Testing

@testable import Helpers

#if os(macOS)
  import AppKit
#endif

@Suite(.timeLimit(.minutes(1)))
struct AppLifecycleTests {
  let center = NotificationCenter()
  let workspaceCenter = NotificationCenter()
  let enterForeground = Notification.Name("test.willEnterForeground")
  let becomeActive = Notification.Name("test.didBecomeActive")
  let enterBackground = Notification.Name("test.didEnterBackground")
  let protectedData = Notification.Name("test.protectedDataDidBecomeAvailable")
  let willSleep = Notification.Name("test.willSleep")
  let didWake = Notification.Name("test.didWake")

  private func observe(initialState: AppLifecycleEvent) -> AsyncStream<AppLifecycleEvent> {
    AppLifecycle.observe(
      [
        (center, enterForeground, .foreground),
        (center, becomeActive, .didBecomeActive),
        (center, enterBackground, .background),
        (center, protectedData, .protectedDataDidBecomeAvailable),
        (workspaceCenter, willSleep, .systemWillSleep),
        (workspaceCenter, didWake, .systemDidWake),
      ],
      initialState: initialState
    )
  }

  @Test
  func theCurrentStateComesFirst() async {
    let events = observe(initialState: .background)

    #expect(await events.first { _ in true } == .background)
  }

  /// A return to the foreground posts `willEnterForeground` and then `didBecomeActive`, and
  /// Control Center posts `didBecomeActive` alone. Each module decides what each one means.
  @Test
  func everyEventPassesInPostingOrder() async {
    let events = observe(initialState: .foreground)

    center.post(name: becomeActive, object: nil)
    center.post(name: enterBackground, object: nil)
    center.post(name: enterForeground, object: nil)
    center.post(name: becomeActive, object: nil)
    center.post(name: protectedData, object: nil)
    workspaceCenter.post(name: willSleep, object: nil)
    workspaceCenter.post(name: didWake, object: nil)

    #expect(
      await events.prefix(8).collect() == [
        .foreground,
        .didBecomeActive,
        .background,
        .foreground,
        .didBecomeActive,
        .protectedDataDidBecomeAvailable,
        .systemWillSleep,
        .systemDidWake,
      ]
    )
  }

  @Test
  func aNotificationOnAnotherCenterIsNotObserved() async {
    let events = observe(initialState: .foreground)

    workspaceCenter.post(name: enterBackground, object: nil)
    center.post(name: willSleep, object: nil)
    center.post(name: becomeActive, object: nil)

    #expect(await events.prefix(2).collect() == [.foreground, .didBecomeActive])
  }

  #if os(macOS)
    /// The Mac posts sleep and wake on the workspace center, not on the default one. Only the
    /// sleep is posted: a wake would probe the socket of every other Realtime client in the
    /// process.
    @Test
    func theMacReportsSleepFromTheWorkspaceCenter() async {
      #expect(!AppLifecycle.live.hasBackgroundState)
      let events = await AppLifecycle.live.events()

      await MainActor.run {
        NSWorkspace.shared.notificationCenter.post(
          name: NSWorkspace.willSleepNotification, object: nil)
      }

      #expect(await events.prefix(2).collect() == [.foreground, .systemWillSleep])
    }
  #elseif !canImport(Darwin)
    @Test
    func withoutAnAppLifecycleTheStreamIsTheForegroundOnly() async {
      #expect(!AppLifecycle.live.hasBackgroundState)

      #expect(await AppLifecycle.live.events().collect() == [.foreground])
    }
  #else
    @Test
    func uiKitAndWatchKitAppsHaveABackgroundState() {
      #expect(AppLifecycle.live.hasBackgroundState)
    }
  #endif
}
