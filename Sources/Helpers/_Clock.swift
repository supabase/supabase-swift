//
//  _Clock.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/01/25.
//

import Clocks
import Foundation

// MARK: - Clock Extensions

extension ContinuousClock {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}

extension TestClock<Duration> {
  package func sleep(for duration: TimeInterval) async throws {
    try await sleep(for: .seconds(duration))
  }
}

// MARK: - Global Clock Instance

private let __clock = ContinuousClock()

#if DEBUG
  package var _clock: ContinuousClock {
    get {
      __clock
    }
    set {
      // In debug mode, we can't actually change the global clock
      // This is a limitation of the simplified approach
      // For testing, use dependency injection instead
    }
  }
#else
  package var _clock: ContinuousClock {
    __clock
  }
#endif
