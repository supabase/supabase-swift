//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 23/12/23.
//

import Foundation
import Helpers

@available(*, deprecated, renamed: "RealtimeMessage")
public typealias Message = RealtimeMessage

extension RealtimeClientV2 {
  @available(*, deprecated, renamed: "channels")
  public var subscriptions: [String: RealtimeChannelV2] {
    channels
  }

  @available(*, deprecated, renamed: "RealtimeClientOptions")
  public struct Configuration: Sendable {
    var url: URL
    var apiKey: String
    var headers: [String: String]
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var timeoutInterval: TimeInterval
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool
    var logger: (any SupabaseLogger)?

    public init(
      url: URL,
      apiKey: String,
      headers: [String: String] = [:],
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      timeoutInterval: TimeInterval = 10,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true,
      logger: (any SupabaseLogger)? = nil
    ) {
      self.url = url
      self.apiKey = apiKey
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.timeoutInterval = timeoutInterval
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
      self.logger = logger
    }
  }

  @available(*, deprecated, renamed: "RealtimeClientStatus")
  public typealias Status = RealtimeClientStatus

  @available(*, deprecated, renamed: "RealtimeClientV2.init(url:options:)")
  public convenience init(config: Configuration) {
    self.init(
      url: config.url,
      options: RealtimeClientOptions(
        headers: config.headers,
        heartbeatInterval: config.heartbeatInterval,
        reconnectDelay: config.reconnectDelay,
        timeoutInterval: config.timeoutInterval,
        disconnectOnSessionLoss: config.disconnectOnSessionLoss,
        connectOnSubscribe: config.connectOnSubscribe,
        logger: config.logger
      )
    )
  }
}

extension RealtimeChannelV2 {
  @available(*, deprecated, renamed: "RealtimeSubscription")
  public typealias Subscription = ObservationToken

  @available(*, deprecated, renamed: "RealtimeChannelStatus")
  public typealias Status = RealtimeChannelStatus
}

extension RealtimeChannelV2 {
  @_disfavoredOverload
  @available(*, deprecated, message: "Use `onBroadcast(event:callback:)` with `BroadcastEvent` instead.")
  public func onBroadcast(
    event: String,
    callback: @escaping @Sendable (JSONObject) -> Void
  ) -> RealtimeSubscription {
    self.onBroadcast(event: event) { (payload: BroadcastEvent) in
      callback(try! JSONObject(payload))
    }
  }

  @_disfavoredOverload
  @available(*, deprecated, message: "Use `broadcastStream(event:)` with `BroadcastEvent` instead.")
  public func broadcastStream(event: String) -> AsyncStream<JSONObject> {
    self.broadcastStream(event: event).map { (payload: BroadcastEvent) in
      try! JSONObject(payload)
    }
    .eraseToStream()
  }
}
