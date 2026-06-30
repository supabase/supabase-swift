//
//  ChannelState.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

public enum ChannelState: Sendable, Equatable {
  case unsubscribed
  case joining
  case joined
  case leaving
  case closed(CloseReason)
}

public enum CloseReason: Sendable, Equatable {
  case userRequested
  case clientDisconnected
  case serverClosed(code: Int?, message: String?)
  case timeout
  case unauthorized
  case policyViolation(String)
  case transportFailure
}
