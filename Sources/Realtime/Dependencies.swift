//
//  Dependencies.swift
//
//
//  Created by Guilherme Souza on 24/11/23.
//

import Foundation

enum Dependencies {
  static var makeTimeoutTimer: () -> TimeoutTimerProtocol = {
    TimeoutTimer()
  }

  static var makeHeartbeatTimer: (_ timeInterval: TimeInterval, _ leeway: TimeInterval)
    -> HeartbeatTimerProtocol = {
      HeartbeatTimer(timeInterval: $0, leeway: $1)
    }
}
