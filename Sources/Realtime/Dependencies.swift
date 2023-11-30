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

  static var makeHeartbeatTimer: (_ timeInterval: TimeInterval, _ leeway: TimeInterval)
    -> HeartbeatTimer = {
      HeartbeatTimer.timer(timeInterval: $0, leeway: $1)
    }
}
