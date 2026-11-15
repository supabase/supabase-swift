//
//  RealtimeNetworkPathObserverTests.swift
//  RealtimeTests
//

import Foundation
import Testing

@testable import Realtime

#if canImport(Network)
  import Network

  /// `NWPath` has no public initializer, so the tests feed the hint the statuses a monitor reports.
  @Suite
  struct RealtimeNetworkPathObserverTests {
    private func wakeCount(afterReporting statuses: [NWPath.Status]) async -> Int {
      let (inputs, inbox) = AsyncStream.makeStream(of: Input.self)
      let hint = NetworkPathWakeHint(inbox: inbox)
      for status in statuses {
        hint.report(status)
      }
      inbox.finish()

      var wakes = 0
      for await input in inputs {
        if case .wake = input { wakes += 1 }
      }
      return wakes
    }

    /// The monitor reports the current path when it starts. That is not a change.
    @Test
    func theFirstReportIsABaselineNotAWake() async {
      #expect(await wakeCount(afterReporting: [.satisfied]) == 0)
    }

    @Test
    func aSatisfiedReportAfterTheBaselineWakes() async {
      #expect(await wakeCount(afterReporting: [.unsatisfied, .satisfied]) == 1)
    }

    /// The path can flap between satisfied reports, and each one after the baseline is a hint.
    @Test
    func everySatisfiedReportAfterTheBaselineWakes() async {
      #expect(
        await wakeCount(afterReporting: [.satisfied, .satisfied, .unsatisfied, .satisfied]) == 2)
    }

    @Test
    func unsatisfiedReportsNeverWake() async {
      #expect(await wakeCount(afterReporting: [.satisfied, .unsatisfied, .unsatisfied]) == 0)
    }

    /// `requiresConnection` means a connection attempt may bring the path up, not that it is up.
    @Test
    func requiresConnectionIsNotAWake() async {
      #expect(await wakeCount(afterReporting: [.unsatisfied, .requiresConnection]) == 0)
    }
  }
#endif
