//
//  SubscriptionStateMachine.swift
//  Supabase
//
//  Created by Guilherme Souza on 18/11/25.
//

import Foundation
import Helpers

actor SubscriptionStateMachine {
  /// Represents the possible states of a channel subscription
  enum State: Sendable {
    case unsubscribed
    case subscribing(Task<Void, any Error>)
    case subscribed(joinRef: String)
    case unsubscribing(Task<Void, Never>)
  }

  // MARK: - Properties

  private(set) var state: State = .unsubscribed

  private let topic: String
  private let maxRetryAttempts: Int
  private let timeoutInterval: TimeInterval
  private let logger: (any SupabaseLogger)?

  // MARK: - Initialization

  init(
    topic: String,
    maxRetryAttempts: Int,
    timeoutInterval: TimeInterval,
    logger: (any SupabaseLogger)?
  ) {
    self.topic = topic
    self.maxRetryAttempts = maxRetryAttempts
    self.timeoutInterval = timeoutInterval
    self.logger = logger
  }

  // MARK: - Public API

  /// Subscribe to the channel. Returns immediately if already subscribed.
  ///
  /// This method is safe to call multiple times - it will reuse an existing subscription
  /// or wait for an in-progress subscription attempt to complete.
  ///
  /// - Parameter performSubscription: Closure that performs the actual subscription
  /// - Returns: The join reference for the subscription
  /// - Throws: Subscription errors or timeout
  func subscribe(
    performSubscription: @escaping @Sendable () async throws -> String
  ) async throws -> String {
    switch state {
    case .subscribed(let joinRef):
      logger?.debug("Already subscribed to channel '\(topic)'")
      return joinRef

    case .subscribing(let task):
      logger?.debug("Subscription already in progress for '\(topic)', waiting...")
      try await task.value
      // Recursively call to get the join ref after task completes
      return try await subscribe(performSubscription: performSubscription)

    case .unsubscribing(let task):
      logger?.debug("Unsubscription in progress for '\(topic)', waiting...")
      await task.value
      return try await subscribe(performSubscription: performSubscription)

    case .unsubscribed:
      logger?.debug("Initiating subscription to channel '\(topic)'")
      return try await performSubscriptionWithRetry(performSubscription: performSubscription)
    }
  }

  /// Unsubscribe from the channel.
  ///
  /// - Parameter performUnsubscription: Closure that performs the actual unsubscription
  func unsubscribe(
    performUnsubscription: @escaping @Sendable () async -> Void
  ) async {
    switch state {
    case .unsubscribed:
      logger?.debug("Already unsubscribed from channel '\(topic)'")
      return

    case .unsubscribing(let task):
      logger?.debug("Unsubscription already in progress for '\(topic)', waiting...")
      await task.value
      return

    case .subscribing(let task):
      logger?.debug("Cancelling subscription attempt for '\(topic)'")
      task.cancel()
      state = .unsubscribed
      return

    case .subscribed:
      logger?.debug("Unsubscribing from channel '\(topic)'")
      let unsubscribeTask = Task<Void, Never> {
        await performUnsubscription()
        state = .unsubscribed
      }

      state = .unsubscribing(unsubscribeTask)
      await unsubscribeTask.value
    }
  }

  /// Mark the subscription as successfully subscribed.
  ///
  /// - Parameter joinRef: The join reference received from the server
  func didSubscribe(joinRef: String) {
    guard case .subscribing = state else {
      logger?.debug("Ignoring didSubscribe in non-subscribing state")
      return
    }

    logger?.debug("Successfully subscribed to channel '\(topic)'")
    state = .subscribed(joinRef: joinRef)
  }

  /// Handle subscription error.
  func handleError(_ error: any Error) {
    guard case .subscribing = state else {
      logger?.debug("Ignoring subscription error in non-subscribing state: \(error)")
      return
    }

    logger?.error("Subscription error for channel '\(topic)': \(error.localizedDescription)")
    state = .unsubscribed
  }

  /// Get current join reference if subscribed, nil otherwise.
  var joinRef: String? {
    if case .subscribed(let joinRef) = state {
      return joinRef
    }
    return nil
  }

  /// Check if currently subscribed.
  var isSubscribed: Bool {
    if case .subscribed = state {
      return true
    }
    return false
  }

  /// Check if currently subscribing.
  var isSubscribing: Bool {
    if case .subscribing = state {
      return true
    }
    return false
  }

  // MARK: - Private Helpers

  private func performSubscriptionWithRetry(
    performSubscription: @escaping @Sendable () async throws -> String
  ) async throws -> String {
    logger?.debug(
      "Starting subscription to channel '\(topic)' (max attempts: \(maxRetryAttempts))"
    )

    let subscriptionTask = Task<Void, any Error> {
      var attempts = 0

      while attempts < maxRetryAttempts {
        attempts += 1

        do {
          logger?.debug(
            "Attempting to subscribe to channel '\(topic)' (attempt \(attempts)/\(maxRetryAttempts))"
          )

          let joinRef: String? = try await withTimeout(interval: timeoutInterval) {
            do {
              return try await performSubscription()
            } catch {
              self.logger?.error("Error when perfoming subscription: \(error.localizedDescription)")
              return nil
            }
          }

          if let joinRef {
            state = .subscribed(joinRef: joinRef)
            logger?.debug("Successfully subscribed to channel '\(topic)'")
          } else {
            state = .unsubscribed
            logger?.error("Failed to subscribe to channel '\(topic)', no join ref received")
          }
          return

        } catch is TimeoutError {
          logger?.debug(
            "Subscribe timed out for channel '\(topic)' (attempt \(attempts)/\(maxRetryAttempts))"
          )

          if attempts < maxRetryAttempts {
            let delay = calculateRetryDelay(for: attempts)
            logger?.debug(
              "Retrying subscription to channel '\(topic)' in \(String(format: "%.2f", delay)) seconds..."
            )

            do {
              try await _clock.sleep(for: delay)

              if Task.isCancelled {
                logger?.debug("Subscription retry cancelled for channel '\(topic)'")
                throw CancellationError()
              }
            } catch {
              logger?.debug("Subscription retry cancelled for channel '\(topic)'")
              throw CancellationError()
            }
          } else {
            logger?.error(
              "Failed to subscribe to channel '\(topic)' after \(maxRetryAttempts) attempts due to timeout"
            )
          }
        } catch is CancellationError {
          logger?.debug("Subscription cancelled for channel '\(topic)'")
          throw CancellationError()
        } catch {
          logger?.error("Subscription failed for channel '\(topic)': \(error.localizedDescription)")
          throw error
        }
      }

      logger?.error("Subscription to channel '\(topic)' failed after \(attempts) attempts")
      throw RealtimeError.maxRetryAttemptsReached
    }

    state = .subscribing(subscriptionTask)

    do {
      try await subscriptionTask.value

      // Get the join ref that was just set
      guard case .subscribed(let joinRef) = state else {
        throw RealtimeError("Subscription succeeded but state is invalid")
      }

      return joinRef
    } catch {
      state = .unsubscribed
      throw error
    }
  }

  /// Calculates retry delay with exponential backoff and jitter
  private func calculateRetryDelay(for attempt: Int) -> TimeInterval {
    let baseDelay: TimeInterval = 1.0
    let maxDelay: TimeInterval = 30.0
    let backoffMultiplier: Double = 2.0

    let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
    let cappedDelay = min(exponentialDelay, maxDelay)

    // Add jitter (±25% random variation) to prevent thundering herd
    let jitterRange = cappedDelay * 0.25
    let jitter = Double.random(in: -jitterRange...jitterRange)

    return max(0.1, cappedDelay + jitter)
  }
}
