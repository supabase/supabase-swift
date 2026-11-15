//
//  ChannelTable.swift
//  Realtime
//

import Foundation

/// The channel records of ``RealtimeCore``, with an index of the channels of each wire topic, so
/// routing a frame looks only at the records of its topic.
///
/// The table keeps the two in step: ``setRecord(_:for:)`` is the only way to add or drop a
/// record, and ``update(_:_:)`` changes a record in place but cannot add, drop, or move it to
/// another topic, as a record's wire topic never changes.
struct ChannelTable {
  private(set) var records: [ChannelID: ChannelRecord] = [:]
  /// The channels of each wire topic, in creation order.
  private(set) var idsByWireTopic: [String: [ChannelID]] = [:]

  subscript(channel: ChannelID) -> ChannelRecord? {
    records[channel]
  }

  var ids: Dictionary<ChannelID, ChannelRecord>.Keys {
    records.keys
  }

  var isEmpty: Bool {
    records.isEmpty
  }

  /// Stores `record` for `channel`, or drops the channel's record when `record` is `nil`, and
  /// updates ``idsByWireTopic`` to match.
  mutating func setRecord(_ record: ChannelRecord?, for channel: ChannelID) {
    let old =
      if let record {
        records.updateValue(record, forKey: channel)
      } else {
        records.removeValue(forKey: channel)
      }
    let oldTopic = old?.wireTopic
    let newTopic = record?.wireTopic
    guard oldTopic != newTopic else { return }
    if let oldTopic {
      idsByWireTopic[oldTopic]?.removeAll { $0 == channel }
      if idsByWireTopic[oldTopic]?.isEmpty == true {
        idsByWireTopic[oldTopic] = nil
      }
    }
    if let newTopic {
      // Channel ids grow in creation order.
      var ids = idsByWireTopic.removeValue(forKey: newTopic) ?? []
      ids.insert(channel, at: ids.firstIndex { $0 > channel } ?? ids.endIndex)
      idsByWireTopic[newTopic] = ids
    }
  }

  /// Runs `body` on the record of `channel` in place, so the record's storage is not copied.
  /// Returns `nil`, without running `body`, when the channel has no record.
  @discardableResult
  mutating func update<Result>(
    _ channel: ChannelID, _ body: (inout ChannelRecord) -> Result
  ) -> Result? {
    guard let index = records.index(forKey: channel) else { return nil }
    return body(&records.values[index])
  }

  /// The first channel in creation order on `wireTopic` whose record matches `predicate`.
  func first(onWireTopic wireTopic: String, where predicate: (ChannelRecord) -> Bool)
    -> ChannelID?
  {
    idsByWireTopic[wireTopic]?.first { records[$0].map(predicate) == true }
  }
}

extension ChannelTable: Sequence {
  func makeIterator() -> Dictionary<ChannelID, ChannelRecord>.Iterator {
    records.makeIterator()
  }
}
