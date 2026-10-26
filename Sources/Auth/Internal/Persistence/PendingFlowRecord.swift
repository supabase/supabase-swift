import Foundation

/// One pending PKCE flow, stored as its own JSON record under `<storageKey>-flow-<id>`.
///
/// One record per flow means two flows started together cannot overwrite each other's verifier.
/// There is no single shared slot to fall back to: an exchange without its record fails.
struct PendingFlowRecord: Codable, Hashable, Sendable {
  enum Purpose: String, Codable, Sendable {
    case signIn = "sign_in"
    case recovery
    case emailChange = "email_change"
    case linkIdentity = "link_identity"
  }

  static let timeToLive: TimeInterval = 60 * 60

  var id: UUID
  var verifier: String
  var purpose: Purpose
  var redirectTo: URL?
  var createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case verifier
    case purpose
    case redirectTo = "redirect_to"
    case createdAt = "created_at"
  }

  static func key(id: UUID, storageKey: String) -> String {
    "\(storageKey)-flow-\(id.uuidString.lowercased())"
  }

  static func isExpired(createdAt: Date, at now: Date) -> Bool {
    now.timeIntervalSince(createdAt) >= timeToLive
  }

  static func decode(_ data: Data) throws -> PendingFlowRecord {
    try PersistedJSON.decoder.decode(PendingFlowRecord.self, from: data)
  }

  func encoded() throws -> Data {
    try PersistedJSON.encoder.encode(self)
  }
}

/// The pending PKCE flows, oldest first, stored as JSON under `<storageKey>-flows`.
///
/// The index lets the client find and expire flows without reading every record. It keeps at most
/// ``maximumCount`` flows, each for at most ``PendingFlowRecord/timeToLive``.
struct PendingFlowIndex: Codable, Hashable, Sendable {
  struct Entry: Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
      case id
      case createdAt = "created_at"
    }
  }

  static let maximumCount = 5

  var flows: [Entry] = []

  static func key(storageKey: String) -> String {
    "\(storageKey)-flows"
  }

  /// Appends `entry`, then drops expired flows and the oldest flows beyond ``maximumCount``.
  ///
  /// - Returns: The IDs of the dropped flows, whose records the caller removes.
  mutating func insert(_ entry: Entry, now: Date) -> [UUID] {
    flows.append(entry)
    var dropped: [UUID] = []
    flows.removeAll { flow in
      guard PendingFlowRecord.isExpired(createdAt: flow.createdAt, at: now) else { return false }
      dropped.append(flow.id)
      return true
    }
    while flows.count > Self.maximumCount {
      dropped.append(flows.removeFirst().id)
    }
    return dropped
  }

  mutating func remove(id: UUID) {
    flows.removeAll { $0.id == id }
  }

  static func decode(_ data: Data) throws -> PendingFlowIndex {
    try PersistedJSON.decoder.decode(PendingFlowIndex.self, from: data)
  }

  func encoded() throws -> Data {
    try PersistedJSON.encoder.encode(self)
  }
}
