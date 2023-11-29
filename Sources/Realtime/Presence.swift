// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import ConcurrencyExtras
import Foundation

/// The Presence object provides features for syncing presence information from
/// the server with the client and handling presences joining and leaving.
///
/// ## Syncing state from the server
///
/// To sync presence state from the server, first instantiate an object and pass
/// your channel in to track lifecycle events:
///
///     let channel = socket.channel("some:topic")
///     let presence = Presence(channel)
///
/// If you have custom syncing state events, you can configure the `Presence`
/// object to use those instead.
///
///     let options = Options(events: [.state: "my_state", .diff: "my_diff"])
///     let presence = Presence(channel, opts: options)
///
/// Next, use the presence.onSync callback to react to state changes from the
/// server. For example, to render the list of users every time the list
/// changes, you could write:
///
///     presence.onSync { renderUsers(presence.list()) }
///
/// ## Listing Presences
///
/// presence.list is used to return a list of presence information based on the
/// local state of metadata. By default, all presence metadata is returned, but
/// a listBy function can be supplied to allow the client to select which
/// metadata to use for a given presence. For example, you may have a user
/// online from different devices with a metadata status of "online", but they
/// have set themselves to "away" on another device. In this case, the app may
/// choose to use the "away" status for what appears on the UI. The example
/// below defines a listBy function which prioritizes the first metadata which
/// was registered for each user. This could be the first tab they opened, or
/// the first device they came online from:
///
///     let listBy: (String, Presence.Map) -> Presence.Meta = { id, pres in
///         let first = pres["metas"]!.first!
///         first["count"] = pres["metas"]!.count
///         first["id"] = id
///         return first
///     }
///     let onlineUsers = presence.list(by: listBy)
///
/// (NOTE: The underlying behavior is a `map` on the `presence.state`. You are
/// mapping the `state` dictionary into whatever datastructure suites your needs)
///
/// ## Handling individual presence join and leave events
///
/// The presence.onJoin and presence.onLeave callbacks can be used to react to
/// individual presences joining and leaving the app. For example:
///
///     let presence = Presence(channel)
///     presence.onJoin { [weak self] (key, current, newPres) in
///         if let cur = current {
///             print("user additional presence", cur)
///         } else {
///             print("user entered for the first time", newPres)
///         }
///     }
///
///     presence.onLeave { [weak self] (key, current, leftPres) in
///         if current["metas"]?.isEmpty == true {
///             print("user has left from all devices", leftPres)
///         } else {
///             print("user left from a device", current)
///         }
///     }
///
///     presence.onSync { renderUsers(presence.list()) }
public final class Presence: @unchecked Sendable {
  // ----------------------------------------------------------------------

  // MARK: - Enums and Structs

  // ----------------------------------------------------------------------
  /// Custom options that can be provided when creating Presence
  ///
  /// ### Example:
  ///
  ///     let options = Options(events: [.state: "my_state", .diff: "my_diff"])
  ///     let presence = Presence(channel, opts: options)
  public struct Options {
    let events: [Events: String]

    /// Default set of Options used when creating Presence. Uses the
    /// phoenix events "presence_state" and "presence_diff"
    public static let defaults = Options(events: [
      .state: "presence_state",
      .diff: "presence_diff",
    ])

    public init(events: [Events: String]) {
      self.events = events
    }
  }

  /// Presence Events
  public enum Events: String {
    case state
    case diff
  }

  struct MutableState {
    var channel: RealtimeChannel?
    var caller = Caller()
    var state: State = [:]
    var pendingDiffs: [Diff] = []
    var joinRef: String?

    var isPendingSyncState: Bool {
      guard let safeJoinRef = joinRef else { return true }
      let channelJoinRef = channel?.joinRef
      return safeJoinRef != channelJoinRef
    }
  }

  let mutableState = LockIsolated(MutableState())

  // ----------------------------------------------------------------------

  // MARK: - Typaliases

  // ----------------------------------------------------------------------
  /// Meta details of a Presence. Just a dictionary of properties
  public typealias Meta = [String: Any]

  /// A mapping of a String to an array of Metas. e.g. {"metas": [{id: 1}]}
  public typealias Map = [String: [Meta]]

  /// A mapping of a Presence state to a mapping of Metas
  public typealias State = [String: Map]

  // Diff has keys "joins" and "leaves", pointing to a Presence.State each
  // containing the users that joined and left.
  public typealias Diff = [String: State]

  /// Closure signature of OnJoin callbacks
  public typealias OnJoin = @Sendable (_ key: String, _ current: Map?, _ new: Map) -> Void

  /// Closure signature for OnLeave callbacks
  public typealias OnLeave = @Sendable (_ key: String, _ current: Map, _ left: Map) -> Void

  //// Closure signature for OnSync callbacks
  public typealias OnSync = @Sendable () -> Void

  /// Collection of callbacks with default values
  struct Caller {
    var onJoin: OnJoin = { _, _, _ in }
    var onLeave: OnLeave = { _, _, _ in }
    var onSync: OnSync = {}
  }

  // ----------------------------------------------------------------------

  // MARK: - Properties

  // ----------------------------------------------------------------------

  /// The state of the Presence
  public var state: State {
    mutableState.state
  }

  /// Pending `join` and `leave` diffs that need to be synced
  public var pendingDiffs: [Diff] {
    mutableState.pendingDiffs
  }

  /// The channel's joinRef, set when state events occur
  public var joinRef: String? {
    mutableState.joinRef
  }

  public var isPendingSyncState: Bool {
    mutableState.isPendingSyncState
  }

  /// Callback to be informed of joins
  public var onJoin: OnJoin {
    mutableState.caller.onJoin
  }

  /// Set the OnJoin callback
  public func onJoin(_ callback: @escaping OnJoin) {
    mutableState.withValue { $0.caller.onJoin = callback }
  }

  /// Callback to be informed of leaves
  public var onLeave: OnLeave {
    mutableState.caller.onLeave
  }

  /// Set the OnLeave callback
  public func onLeave(_ callback: @escaping OnLeave) {
    mutableState.withValue { $0.caller.onLeave = callback }
  }

  /// Callback to be informed of syncs
  public var onSync: OnSync {
    mutableState.caller.onSync
  }

  /// Set the OnSync callback
  public func onSync(_ callback: @escaping OnSync) {
    mutableState.withValue { $0.caller.onSync = callback }
  }

  public init(channel: RealtimeChannel, opts: Options = Options.defaults) {
    mutableState.withValue { $0.channel = channel }

    guard // Do not subscribe to events if they were not provided
      let stateEvent = opts.events[.state],
      let diffEvent = opts.events[.diff]
    else { return }

    channel.on(stateEvent, filter: ChannelFilter()) { [weak self] message in
      guard
        let self,
        let newState = message.rawPayload as? State
      else { return }

      onStateEvent(newState)
    }

    channel.on(diffEvent, filter: ChannelFilter()) { [weak self] message in
      guard
        let self,
        let diff = message.rawPayload as? Diff
      else { return }

      onDiffEvent(diff)
    }
  }

  private func onStateEvent(_ newState: State) {
    mutableState.withValue { mutableState in
      mutableState.joinRef = mutableState.channel?.joinRef

      let caller = mutableState.caller
      mutableState.state = Presence.syncState(
        mutableState.state,
        newState: newState,
        onJoin: caller.onJoin,
        onLeave: caller.onLeave
      )

      mutableState.pendingDiffs.forEach { diff in
        mutableState.state = Presence.syncDiff(
          mutableState.state,
          diff: diff,
          onJoin: caller.onJoin,
          onLeave: caller.onLeave
        )
      }

      mutableState.pendingDiffs = []
      caller.onSync()
    }
  }

  private func onDiffEvent(_ diff: Diff) {
    mutableState.withValue { mutableState in
      if mutableState.isPendingSyncState {
        mutableState.pendingDiffs.append(diff)
      } else {
        let caller = mutableState.caller
        mutableState.state = Presence.syncDiff(
          mutableState.state,
          diff: diff,
          onJoin: caller.onJoin,
          onLeave: caller.onLeave
        )
        caller.onSync()
      }
    }
  }

  /// Returns the array of presences, with default selected metadata.
  public func list() -> [Map] {
    list(by: { _, pres in pres })
  }

  /// Returns the array of presences, with selected metadata
  public func list<T>(by transformer: (String, Map) -> T) -> [T] {
    Presence.listBy(state, transformer: transformer)
  }

  /// Filter the Presence state with a given function
  public func filter(by filter: ((String, Map) -> Bool)?) -> State {
    Presence.filter(state, by: filter)
  }

  // ----------------------------------------------------------------------

  // MARK: - Static

  // ----------------------------------------------------------------------

  // Used to sync the list of presences on the server
  // with the client's state. An optional `onJoin` and `onLeave` callback can
  // be provided to react to changes in the client's local presences across
  // disconnects and reconnects with the server.
  //
  // - returns: Presence.State
  @discardableResult
  public static func syncState(
    _ currentState: State,
    newState: State,
    onJoin: OnJoin = { _, _, _ in },
    onLeave: OnLeave = { _, _, _ in }
  ) -> State {
    let state = currentState
    var leaves: Presence.State = [:]
    var joins: Presence.State = [:]

    state.forEach { key, presence in
      if newState[key] == nil {
        leaves[key] = presence
      }
    }

    newState.forEach { key, newPresence in
      if let currentPresence = state[key] {
        let newRefs = newPresence["metas"]!.map { $0["phx_ref"] as! String }
        let curRefs = currentPresence["metas"]!.map { $0["phx_ref"] as! String }

        let joinedMetas = newPresence["metas"]!.filter { (meta: Meta) -> Bool in
          !curRefs.contains { $0 == meta["phx_ref"] as! String }
        }
        let leftMetas = currentPresence["metas"]!.filter { (meta: Meta) -> Bool in
          !newRefs.contains { $0 == meta["phx_ref"] as! String }
        }

        if joinedMetas.count > 0 {
          joins[key] = newPresence
          joins[key]!["metas"] = joinedMetas
        }

        if leftMetas.count > 0 {
          leaves[key] = currentPresence
          leaves[key]!["metas"] = leftMetas
        }
      } else {
        joins[key] = newPresence
      }
    }

    return Presence.syncDiff(
      state,
      diff: ["joins": joins, "leaves": leaves],
      onJoin: onJoin,
      onLeave: onLeave
    )
  }

  // Used to sync a diff of presence join and leave
  // events from the server, as they happen. Like `syncState`, `syncDiff`
  // accepts optional `onJoin` and `onLeave` callbacks to react to a user
  // joining or leaving from a device.
  //
  // - returns: Presence.State
  @discardableResult
  public static func syncDiff(
    _ currentState: State,
    diff: Diff,
    onJoin: OnJoin = { _, _, _ in },
    onLeave: OnLeave = { _, _, _ in }
  ) -> State {
    var state = currentState
    diff["joins"]?.forEach { key, newPresence in
      let currentPresence = state[key]
      state[key] = newPresence

      if let curPresence = currentPresence {
        let joinedRefs = state[key]!["metas"]!.map { $0["phx_ref"] as! String }
        let curMetas = curPresence["metas"]!.filter { (meta: Meta) -> Bool in
          !joinedRefs.contains { $0 == meta["phx_ref"] as! String }
        }
        state[key]!["metas"]!.insert(contentsOf: curMetas, at: 0)
      }

      onJoin(key, currentPresence, newPresence)
    }

    diff["leaves"]?.forEach { key, leftPresence in
      guard var curPresence = state[key] else { return }
      let refsToRemove = leftPresence["metas"]!.map { $0["phx_ref"] as! String }
      let keepMetas = curPresence["metas"]!.filter { (meta: Meta) -> Bool in
        !refsToRemove.contains { $0 == meta["phx_ref"] as! String }
      }

      curPresence["metas"] = keepMetas
      onLeave(key, curPresence, leftPresence)

      if keepMetas.count > 0 {
        state[key]!["metas"] = keepMetas
      } else {
        state.removeValue(forKey: key)
      }
    }

    return state
  }

  public static func filter(
    _ presences: State,
    by filter: ((String, Map) -> Bool)?
  ) -> State {
    let safeFilter = filter ?? { _, _ in true }
    return presences.filter(safeFilter)
  }

  public static func listBy<T>(
    _ presences: State,
    transformer: (String, Map) -> T
  ) -> [T] {
    presences.map(transformer)
  }
}
