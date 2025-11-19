//
//  MessageRouter.swift
//  Realtime
//
//  Created on 17/01/25.
//

import Foundation

/// Routes incoming messages to appropriate handlers.
///
/// This actor provides centralized message dispatch, ensuring thread-safe
/// registration and routing of messages to channel and system handlers.
actor MessageRouter {
  // MARK: - Type Definitions

  typealias MessageHandler = @Sendable (RealtimeMessageV2) async -> Void

  // MARK: - Properties

  private var channelHandlers: [String: MessageHandler] = [:]
  private var systemHandlers: [MessageHandler] = []
  private let logger: (any SupabaseLogger)?

  // MARK: - Initialization

  init(logger: (any SupabaseLogger)?) {
    self.logger = logger
  }

  // MARK: - Public API

  /// Register handler for a specific channel topic.
  ///
  /// - Parameters:
  ///   - topic: The channel topic to handle
  ///   - handler: The handler to call for messages on this topic
  func registerChannel(topic: String, handler: @escaping MessageHandler) {
    logger?.debug("Registering message handler for channel: \(topic)")
    channelHandlers[topic] = handler
  }

  /// Unregister channel handler.
  ///
  /// - Parameter topic: The channel topic to unregister
  func unregisterChannel(topic: String) {
    logger?.debug("Unregistering message handler for channel: \(topic)")
    channelHandlers[topic] = nil
  }

  /// Register system-wide message handler.
  ///
  /// System handlers are called for every message, regardless of topic.
  ///
  /// - Parameter handler: The handler to call for all messages
  func registerSystemHandler(_ handler: @escaping MessageHandler) {
    logger?.debug("Registering system message handler")
    systemHandlers.append(handler)
  }

  /// Route message to appropriate handlers.
  ///
  /// This will call all system handlers and the specific channel handler
  /// if one is registered for the message's topic.
  ///
  /// - Parameter message: The message to route
  func route(_ message: RealtimeMessageV2) async {
    logger?.debug("Routing message - topic: \(message.topic), event: \(message.event)")

    // System handlers always run
    for handler in systemHandlers {
      await handler(message)
    }

    // Route to specific channel if registered
    if let handler = channelHandlers[message.topic] {
      await handler(message)
    } else {
      logger?.debug("No handler registered for topic: \(message.topic)")
    }
  }

  /// Remove all handlers.
  func reset() {
    logger?.debug("Resetting message router - removing all handlers")
    channelHandlers.removeAll()
    systemHandlers.removeAll()
  }

  /// Get count of registered channel handlers.
  var channelCount: Int {
    channelHandlers.count
  }
}
