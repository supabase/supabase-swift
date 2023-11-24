//
//  Dependencies.swift
//
//
//  Created by Guilherme Souza on 24/11/23.
//

import Foundation

enum Dependencies {
  static var timeoutTimer: () -> TimeoutTimerProtocol = {
    TimeoutTimer()
  }

  static var heartbeatTimer: (
    _ timeInterval: TimeInterval,
    _ queue: DispatchQueue,
    _ leeway: DispatchTimeInterval
  ) -> HeartbeatTimerProtocol = {
    HeartbeatTimer(timeInterval: $0, queue: $1, leeway: $2)
  }
}
