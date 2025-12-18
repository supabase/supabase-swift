//
//  _Clock.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/01/25.
//

import Clocks
import ConcurrencyExtras
import Foundation

package protocol _Clock: Sendable {
  func sleep(for duration: TimeInterval) async throws
}

extension ContinuousClock: _Clock {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}
extension TestClock<Duration>: _Clock {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}

let _resolveClock: @Sendable () -> any _Clock = {
  ContinuousClock()
}

private let __clock = LockIsolated(_resolveClock())

#if DEBUG
  package var _clock: any _Clock {
    get {
      __clock.value
    }
    set {
      __clock.setValue(newValue)
    }
  }
#else
  package var _clock: any _Clock {
    __clock.value
  }
#endif
