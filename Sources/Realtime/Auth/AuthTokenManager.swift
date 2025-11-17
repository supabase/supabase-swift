//
//  AuthTokenManager.swift
//  Realtime
//
//  Created on 17/01/25.
//

import Foundation

/// Manages authentication token lifecycle and distribution.
///
/// This actor provides a single source of truth for the current authentication token,
/// handling both direct token assignment and token provider callbacks.
actor AuthTokenManager {
  // MARK: - Properties

  private var currentToken: String?
  private let tokenProvider: (@Sendable () async throws -> String?)?

  // MARK: - Initialization

  init(
    initialToken: String?,
    tokenProvider: (@Sendable () async throws -> String?)?
  ) {
    self.currentToken = initialToken
    self.tokenProvider = tokenProvider
  }

  // MARK: - Public API

  /// Get current token, calling provider if needed.
  ///
  /// If no current token is set, this will attempt to fetch from the token provider.
  ///
  /// - Returns: The current authentication token, or nil if unavailable
  func getCurrentToken() async -> String? {
    // Return current token if available
    if let token = currentToken {
      return token
    }

    // Try to get from provider
    if let provider = tokenProvider {
      let token = try? await provider()
      currentToken = token
      return token
    }

    return nil
  }

  /// Update token and return if it changed.
  ///
  /// - Parameter token: The new token to set, or nil to clear
  /// - Returns: True if the token changed, false if it's the same
  func updateToken(_ token: String?) async -> Bool {
    guard token != currentToken else {
      return false
    }

    currentToken = token
    return true
  }

  /// Refresh token from provider if available.
  ///
  /// This forces a call to the token provider even if a current token exists.
  ///
  /// - Returns: The refreshed token, or current token if no provider
  func refreshToken() async -> String? {
    guard let provider = tokenProvider else {
      return currentToken
    }

    let token = try? await provider()
    currentToken = token
    return token
  }

  /// Get the current token without calling the provider.
  ///
  /// - Returns: The currently stored token, or nil
  var token: String? {
    currentToken
  }
}
