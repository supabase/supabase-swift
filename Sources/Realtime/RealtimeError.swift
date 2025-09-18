//
//  RealtimeError.swift
//
//
//  Created by Guilherme Souza on 30/10/23.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct RealtimeError: SupabaseError {
  public var errorDescription: String?
  public var underlyingData: Data?
  public var underlyingResponse: HTTPURLResponse?
  public var context: [String: String]

  public init(
    _ errorDescription: String,
    underlyingData: Data? = nil,
    underlyingResponse: HTTPURLResponse? = nil,
    context: [String: String] = [:]
  ) {
    self.errorDescription = errorDescription
    self.underlyingData = underlyingData
    self.underlyingResponse = underlyingResponse
    self.context = context
  }
  
  // MARK: - SupabaseError Protocol Conformance
  
  public var errorCode: String {
    if let errorDesc = errorDescription {
      switch errorDesc.lowercased() {
      case let desc where desc.contains("connection failed"):
        return SupabaseErrorCode.connectionFailed.rawValue
      case let desc where desc.contains("subscription failed"):
        return SupabaseErrorCode.subscriptionFailed.rawValue
      case let desc where desc.contains("maximum retry attempts"):
        return SupabaseErrorCode.maxRetryAttemptsReached.rawValue
      default:
        return SupabaseErrorCode.unknown.rawValue
      }
    }
    return SupabaseErrorCode.unknown.rawValue
  }
}

extension RealtimeError {
  /// The maximum retry attempts reached.
  public static var maxRetryAttemptsReached: Self {
    Self("Maximum retry attempts reached.")
  }
  
  /// Connection failed error.
  public static var connectionFailed: Self {
    Self("Connection failed.")
  }
  
  /// Subscription failed error.
  public static var subscriptionFailed: Self {
    Self("Subscription failed.")
  }
}
