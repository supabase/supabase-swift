//
//  ChannelState.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

public enum ChannelState: Sendable, Equatable {
  case unsubscribed
  case joining
  case joined
  case leaving
  case closed(CloseReason)
}
