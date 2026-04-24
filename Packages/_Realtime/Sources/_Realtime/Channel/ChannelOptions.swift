//
//  ChannelOptions.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public struct ChannelOptions: Sendable {
  public var isPrivate: Bool = false
  public var broadcast: BroadcastOptions = .init()
  public var presenceKey: String? = nil
  public init() {}
}

public struct BroadcastOptions: Sendable {
  public var acknowledge: Bool = false
  public var receiveOwnBroadcasts: Bool = false
  public var replay: ReplayOption? = nil
  public init() {}
}

public struct ReplayOption: Sendable {
  public var since: Date
  public var limit: Int?
  public init(since: Date, limit: Int? = nil) {
    self.since = since
    self.limit = limit
  }
}
