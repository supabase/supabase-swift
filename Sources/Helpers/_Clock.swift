//
//  _Clock.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/01/25.
//

import Clocks
import ConcurrencyExtras
import Foundation

private let __clock: LockIsolated<any Clock<Duration>> = LockIsolated(ContinuousClock())

#if DEBUG
  package var _clock: any Clock<Duration> {
    get {
      __clock.value
    }
    set {
      __clock.setValue(newValue)
    }
  }
#else
  package var _clock: any Clock<Duration> {
    __clock.value
  }
#endif
