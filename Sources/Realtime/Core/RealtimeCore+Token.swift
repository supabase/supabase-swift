//
//  RealtimeCore+Token.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

extension RealtimeCore {
  /// Stores `token` and sends it to the joined channels. `nil` asks the `accessToken` callback
  /// for one instead.
  mutating func setAuth(_ token: String?) -> [Effect] {
    guard let token else {
      return refreshAccessToken(ignoringInterval: false)
    }
    // An unchanged token must not start a new generation: that would drop a newer token from a
    // callback call in flight.
    guard token != tokens.token, tokens.apply(token, generation: tokens.beginRefresh()) else {
      return []
    }
    return scheduleTokenRefresh() + pushAccessToken(token)
  }

  /// Calls the `accessToken` callback, unless a call is in flight or, without
  /// `ignoringInterval`, the last one is less than ``Options/accessTokenRefreshInterval`` old.
  mutating func refreshAccessToken(ignoringInterval: Bool) -> [Effect] {
    guard options.hasAccessTokenProvider, !tokenFetchInFlight else { return [] }
    if !ignoringInterval, let last = lastTokenFetch,
      now.elapsed - last < options.accessTokenRefreshInterval
    {
      return []
    }
    lastTokenFetch = now.elapsed
    tokenFetchInFlight = true
    return [.fetchAccessToken(generation: tokens.beginRefresh())]
  }

  /// Applies the callback's result. A result from before a newer token was set is dropped. The
  /// channels waiting for a token then join with the stored one, and a new token goes to the
  /// joined channels.
  mutating func tokenFetched(_ token: String?, generation: Int) -> [Effect] {
    guard tokenFetchInFlight else { return [] }
    tokenFetchInFlight = false

    var effects: [Effect] = []
    var stored = false
    if generation == tokens.generation {
      stored = tokens.apply(token, generation: generation)
      // Scheduled even when nothing changed, so a callback that failed or returned the same
      // token is asked again.
      effects += scheduleTokenRefresh()
    } else {
      logger.debug("Dropping an access token fetched before a newer one was set")
    }

    let waiting = channels.keys.sorted().filter {
      if case .refreshingToken? = channels[$0]?.phase { true } else { false }
    }
    if tokenRefetchQueued {
      tokenRefetchQueued = false
      if !waiting.isEmpty {
        // The channels wait for the call that started after their token was refused.
        effects += refreshAccessToken(ignoringInterval: true)
      }
    }
    if !tokenFetchInFlight {
      for topic in waiting {
        guard case .refreshingToken(let attempt)? = channels[topic]?.phase else { continue }
        effects += pushJoin(topic, attempt: attempt)
      }
    }
    if stored, let token = tokens.token {
      effects += pushAccessToken(token)
    }
    return effects
  }

  /// Rejoins a channel whose join the server refused for an expired token, with a token the
  /// callback returns after the refusal. A call in flight started before it, so another call
  /// follows that one.
  mutating func rejoinWithFreshToken(_ topic: String, attempt: Int) -> [Effect] {
    channels[topic]?.hasRefreshedExpiredToken = true
    guard options.hasAccessTokenProvider else {
      return sendJoin(topic, attempt: attempt)
    }
    if tokenFetchInFlight {
      tokenRefetchQueued = true
      return waitForToken(topic, attempt: attempt)
    }
    return waitForToken(topic, attempt: attempt) + refreshAccessToken(ignoringInterval: true)
  }

  /// Parks join attempt `attempt` until the callback call in flight returns.
  mutating func waitForToken(_ topic: String, attempt: Int) -> [Effect] {
    // The join after the token replaces any older join.
    channels[topic]?.timedOutJoinRef = nil
    return setPhase(.refreshingToken(attempt: attempt), for: topic)
  }

  mutating func tokenRefreshTimerFired() -> [Effect] {
    tokenRefreshScheduled = false
    // A client that disconnected has no channel to keep alive.
    guard isConnected else { return [] }
    return refreshAccessToken(ignoringInterval: false)
  }

  /// Refreshes ``Options/accessTokenRefreshLeeway`` before the token's `exp`, and never sooner
  /// than ``Options/accessTokenRefreshInterval`` from now. Without a connection, a callback, or
  /// a token with an `exp`, there is nothing to schedule: the next join or heartbeat refreshes
  /// the token instead.
  mutating func scheduleTokenRefresh() -> [Effect] {
    guard options.hasAccessTokenProvider, isConnected,
      let due = tokens.refreshDelay(now: now.date, leeway: options.accessTokenRefreshLeeway)
    else {
      return cancelTokenRefresh()
    }
    tokenRefreshScheduled = true
    return [.schedule(.tokenRefresh, after: max(due, options.accessTokenRefreshInterval))]
  }

  mutating func cancelTokenRefresh() -> [Effect] {
    guard tokenRefreshScheduled else { return [] }
    tokenRefreshScheduled = false
    return [.cancel(.tokenRefresh)]
  }

  /// Sends `token` to every subscribed channel, and to every channel whose `phx_join` already
  /// went out with another token. A channel still waiting for a token joins with this one.
  private mutating func pushAccessToken(_ token: String) -> [Effect] {
    guard isConnected else { return [] }
    var effects: [Effect] = []
    for topic in channels.keys.sorted() {
      guard let record = channels[topic], let joinRef = record.currentJoinRef else { continue }
      let isSubscribed = if case .subscribed = record.phase { true } else { false }
      guard isSubscribed || record.joinAccessToken != token else { continue }
      logger.debug("Updating auth token for channel '\(topic)'")
      effects.append(
        .send(
          RealtimeMessage(
            joinRef: joinRef, ref: makeRef(), topic: RealtimeChannel.wireTopic(for: topic),
            event: ChannelEvent.accessToken, payload: ["access_token": .string(token)])))
    }
    return effects
  }
}
