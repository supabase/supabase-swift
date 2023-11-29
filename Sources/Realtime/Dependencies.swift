//
//  Dependencies.swift
//
//
//  Created by Guilherme Souza on 24/11/23.
//

import Foundation

enum Dependencies {
  static var makeTimeoutTimer: () -> TimeoutTimer = {
    TimeoutTimer.default()
  }

  static var heartbeatTimer: (_ timeInterval: TimeInterval) -> HeartbeatTimer = {
    HeartbeatTimer.default(timeInterval: $0)
  }
}
