//
//  _Clock.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/01/25.
//

import Clocks
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

// For overriding clock on tests, we use a mutable _clock in DEBUG builds.
// nonisolated(unsafe) is safe to use if making sure we assign _clock once in test set up.
//
// _clock is read-only in RELEASE builds.
#if DEBUG
  nonisolated(unsafe) package var _clock = _resolveClock()
#else
  package let _clock = _resolveClock()
#endif
