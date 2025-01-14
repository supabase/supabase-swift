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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension ContinuousClock: _Clock {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension TestClock<Duration>: _Clock {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}

/// `_Clock` used on platforms where ``Clock`` protocol isn't available.
struct FallbackClock: _Clock {
  func sleep(for duration: TimeInterval) async throws {
    try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(duration))
  }
}

// Resolves clock instance based on platform availability.
let _resolveClock: @Sendable () -> any _Clock = {
  if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
    ContinuousClock()
  } else {
    FallbackClock()
  }
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
