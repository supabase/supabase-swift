//
//  World.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/02/25.
//

import ConcurrencyExtras
import Foundation

struct World: Sendable {
  fileprivate static let instance = LockIsolated(World())

  var date: @Sendable () -> Date = { Date() }
  var urlOpener: URLOpener = .live
  var pkce: PKCE = .live
}

#if DEBUG
  var Current: World {
    get { World.instance.value }
    set { World.instance.setValue(newValue) }
  }
#else
  var Current: World {
    World.instance.value
  }
#endif
