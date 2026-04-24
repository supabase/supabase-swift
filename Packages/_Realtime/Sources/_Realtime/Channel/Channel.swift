//
//  Channel.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public final actor Channel: Sendable {
  public let topic: String
  private(set) var options: ChannelOptions
  private weak var realtime: Realtime?

  init(topic: String, options: ChannelOptions, realtime: Realtime) {
    self.topic = topic
    self.options = options
    self.realtime = realtime
  }

  func handle(_ msg: PhoenixMessage) async { /* implemented in Task 3 */ }
  func handleBinaryBroadcast(_ broadcast: BinaryBroadcast) async { /* implemented in Task 3 */ }
  func handleConnectionLoss() async { /* implemented in Task 3 */ }
  func rejoin() async throws(RealtimeError) { /* implemented in Task 3 */ }
}
