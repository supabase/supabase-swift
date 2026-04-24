//
//  Presence.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

public struct Presence: Sendable {
  private let channel: Channel

  init(channel: Channel) { self.channel = channel }

  // MARK: - Track

  public func track<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) -> PresenceHandle {
    guard let realtime = await channel.realtime else { throw .disconnected }

    let data: Data
    do { data = try realtime.configuration.encoder.encode(state) } catch {
      throw .encoding(underlying: error)
    }
    let obj: [String: JSONValue]
    do { obj = try JSONDecoder().decode([String: JSONValue].self, from: data) } catch {
      throw .encoding(underlying: error)
    }

    let topic = channel.topic
    let joinRef = await channel.joinRef
    let trackMsg = PhoenixMessage(
      joinRef: joinRef, ref: nil,
      topic: topic, event: "presence",
      payload: ["event": "track", "payload": .object(obj)]
    )
    _ = try await realtime.sendAndAwait(trackMsg, timeout: realtime.configuration.joinTimeout)

    let trackId = UUID()
    await channel.registerTrack(id: trackId, state: obj)

    let cancelClosure: @Sendable () async throws(RealtimeError) -> Void = {
      await channel.unregisterTrack(id: trackId)
      let untrackMsg = PhoenixMessage(
        joinRef: await channel.joinRef, ref: nil,
        topic: topic, event: "presence",
        payload: ["event": "untrack"]
      )
      _ = try await realtime.sendAndAwait(untrackMsg, timeout: realtime.configuration.joinTimeout)
    }
    return PresenceHandle(cancel: cancelClosure)
  }

  // MARK: - Observe (snapshot stream)

  public func observe<T: Decodable & Sendable>(_: T.Type = T.self) -> AsyncStream<PresenceState<T>> {
    AsyncStream { continuation in
      let id = UUID()
      Task {
        await channel.registerSnapshotHandler(id: id) { rawPayload in
          let state = decodePresenceState(rawPayload, as: T.self)
          continuation.yield(state)
        } finish: {
          continuation.finish()
        }
        continuation.onTermination = { [id] _ in
          Task { await channel.unregisterPresenceHandlers(id: id) }
        }
        do { try await channel.joinIfNeeded() } catch { continuation.finish() }
      }
    }
  }

  // MARK: - Diffs (incremental stream)

  public func diffs<T: Decodable & Sendable>(_: T.Type = T.self) -> AsyncStream<PresenceDiff<T>> {
    AsyncStream { continuation in
      let id = UUID()
      Task {
        await channel.registerDiffHandler(id: id) { rawPayload in
          let diff = decodePresenceDiff(rawPayload, as: T.self)
          continuation.yield(diff)
        } finish: {
          continuation.finish()
        }
        continuation.onTermination = { [id] _ in
          Task { await channel.unregisterPresenceHandlers(id: id) }
        }
        do { try await channel.joinIfNeeded() } catch { continuation.finish() }
      }
    }
  }
}

// MARK: - Decoding

private func decodePresenceState<T: Decodable>(_ raw: [String: JSONValue], as: T.Type) -> PresenceState<T> {
  var active: [PresenceKey: [T]] = [:]
  for (key, val) in raw {
    guard case .object(let entry) = val,
          case .array(let metas) = entry["metas"] else { continue }
    active[key] = metas.compactMap { metaVal -> T? in
      guard case .object(let metaObj) = metaVal,
            let data = try? JSONEncoder().encode(metaObj),
            let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
      return decoded
    }
  }
  return PresenceState(active: active, lastDiff: nil)
}

private func decodePresenceDiff<T: Decodable>(_ raw: [String: JSONValue], as: T.Type) -> PresenceDiff<T> {
  func extractEntries(_ val: JSONValue?) -> [(PresenceKey, T)] {
    guard case .object(let dict) = val else { return [] }
    return dict.flatMap { key, entry -> [(PresenceKey, T)] in
      guard case .object(let entryObj) = entry,
            case .array(let metas) = entryObj["metas"] else { return [] }
      return metas.compactMap { metaVal -> (PresenceKey, T)? in
        guard case .object(let metaObj) = metaVal,
              let data = try? JSONEncoder().encode(metaObj),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return (key, decoded)
      }
    }
  }
  return PresenceDiff(joined: extractEntries(raw["joins"]), left: extractEntries(raw["leaves"]))
}
