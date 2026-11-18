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
    let generation = tokens.beginRefresh()
    tokenFetchGeneration = generation
    return [.fetchAccessToken(generation: generation)]
  }

  /// How one `accessToken` callback call ended.
  enum TokenFetchResult {
    /// The callback returned. `nil` means no signed-in user.
    case returned(String?)
    /// The callback threw or did not return in time. The stored token stays.
    case failed
  }

  /// Applies the result of the fetch in flight; a result for any other fetch is ignored. Its
  /// token is dropped when a newer token was set during the fetch. A `nil` token clears the
  /// stored one; a failure keeps it. The channels waiting for a token then join with the stored
  /// one, and a change goes to the joined channels.
  mutating func tokenFetched(_ result: TokenFetchResult, generation: Int) -> [Effect] {
    guard generation == tokenFetchGeneration else {
      logger.debug("Ignoring the result of access token fetch \(generation): not in flight")
      return []
    }
    tokenFetchGeneration = nil

    var effects: [Effect] = []
    var stored = false
    if generation == tokens.generation {
      if case .returned(let token) = result {
        stored = tokens.apply(token, generation: generation)
      }
      // Scheduled even when nothing changed, so a callback that failed or returned the same
      // token is asked again.
      effects += scheduleTokenRefresh()
    } else {
      logger.debug("Dropping an access token fetched before a newer one was set")
    }

    let waiting = channels.ids.sorted().filter {
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
      for channel in waiting {
        guard case .refreshingToken(let attempt)? = channels[channel]?.phase else { continue }
        effects += pushJoin(channel, attempt: attempt)
      }
    }
    // The server ignores an `access_token` push of `null`, so a cleared token is replaced by the
    // API key on the joined channels.
    if stored, let token = tokens.token ?? options.apiKey {
      effects += pushAccessToken(token)
    }
    return effects
  }

  /// Rejoins a channel whose join the server refused for an expired token, with a token the
  /// callback returns after the refusal. A call in flight started before it, so another call
  /// follows that one.
  mutating func rejoinWithFreshToken(_ channel: ChannelID, attempt: Int) -> [Effect] {
    channels.update(channel) { $0.hasRefreshedExpiredToken = true }
    guard options.hasAccessTokenProvider else {
      return sendJoin(channel, attempt: attempt)
    }
    if tokenFetchInFlight {
      tokenRefetchQueued = true
      return waitForToken(channel, attempt: attempt)
    }
    return waitForToken(channel, attempt: attempt) + refreshAccessToken(ignoringInterval: true)
  }

  /// Parks join attempt `attempt` until the callback call in flight returns.
  mutating func waitForToken(_ channel: ChannelID, attempt: Int) -> [Effect] {
    // The join after the token replaces any older join.
    channels.update(channel) { $0.timedOutJoinRef = nil }
    return setPhase(.refreshingToken(attempt: attempt), for: channel)
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
  /// went out and that last sent another token. A channel still waiting for a token joins with
  /// this one.
  private mutating func pushAccessToken(_ token: String) -> [Effect] {
    guard isConnected else { return [] }
    var effects: [Effect] = []
    for channel in channels.ids.sorted() {
      guard let record = channels[channel], let joinRef = record.currentJoinRef else { continue }
      let isSubscribed = if case .subscribed = record.phase { true } else { false }
      // Compared with the last token sent, not the join's: the server may hold a token pushed
      // after the join.
      guard isSubscribed || record.sentAccessToken != token else { continue }
      channels.update(channel) { $0.sentAccessToken = token }
      logger.debug("Updating auth token for channel '\(topic(of: channel))'")
      effects.append(
        .send(
          RealtimeMessage(
            joinRef: joinRef, ref: makeRef(), topic: record.wireTopic,
            event: ChannelEvent.accessToken, payload: ["access_token": .string(token)])))
    }
    return effects
  }
}
