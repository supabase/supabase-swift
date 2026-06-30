//
//  LifecyclePolicy.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

/// Controls how the Realtime connection responds to app lifecycle events.
public enum LifecyclePolicy: Sendable {
  /// The caller manages connection/disconnection manually.
  case manual
  /// The SDK automatically manages the connection based on app lifecycle events.
  case automatic
}

extension LifecyclePolicy {
  /// `.automatic` on iOS/macOS/tvOS/visionOS; `.manual` on watchOS and Linux
  /// where lifecycle observation is not supported.
  public static let automaticDefault: LifecyclePolicy = {
    #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
      return .automatic
    #else
      return .manual
    #endif
  }()
}
