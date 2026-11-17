//
//  ServerPostgresBinding.swift
//  Realtime
//

/// A Postgres binding that the server echoed in a join reply, with the id that its change
/// frames name.
///
/// `event` keeps the raw value, so an event this SDK does not know does not fail the join.
/// ``PostgresChangeEvent`` stays closed because the SDK sends it.
struct ServerPostgresBinding: Decodable, Hashable, Sendable {
  let id: Int
  let event: String?
  let schema: String
  let table: String?
  let filter: String?

  init(id: Int, event: String?, schema: String, table: String?, filter: String?) {
    self.id = id
    self.event = event
    self.schema = schema
    self.table = table
    self.filter = filter
  }

  /// The echo of `binding` as the server sends it for a known event.
  init(_ binding: PostgresJoinConfig, id: Int? = nil) {
    self.init(
      id: id ?? binding.id, event: binding.event?.rawValue, schema: binding.schema,
      table: binding.table, filter: binding.filter)
  }

  /// Whether `change`, which the server matched to this binding, belongs to the client's
  /// `binding`. When the echoed event is one this SDK does not know, the change's own kind
  /// stands in for it.
  func matches(_ binding: PostgresJoinConfig, change: PostgresChange) -> Bool {
    guard schema == binding.schema, table == binding.table, filter == binding.filter else {
      return false
    }
    if binding.event == .all { return true }
    guard let event, PostgresChangeEvent(rawValue: event) == nil else {
      return event == binding.event?.rawValue
    }
    return change.kind.rawValue == binding.event?.rawValue
  }

  /// Decodes one echoed binding, or `nil` when it does not decode, so one bad entry does not
  /// fail the join.
  struct Lossy: Decodable {
    let binding: ServerPostgresBinding?

    init(from decoder: any Decoder) throws {
      binding = try? ServerPostgresBinding(from: decoder)
    }
  }
}
