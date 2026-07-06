//
//  _Clock.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/01/25.
//

import ConcurrencyExtras
package import Foundation

private let __clock = LockIsolated<any Clock<Swift.Duration>>(ContinuousClock())

#if DEBUG
  package var _clock: any Clock<Swift.Duration> {
    get {
      __clock.value
    }
    set {
      __clock.setValue(newValue)
    }
  }
#else
  package var _clock: any Clock<Swift.Duration> {
    __clock.value
  }
#endif
