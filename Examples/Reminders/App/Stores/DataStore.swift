import Foundation
import Observation
import Supabase

/// All the data of the signed-in user, in memory.
///
/// Views read from this object and call its methods to write. Nothing is saved on the
/// device: `load()` reads from the server, and Realtime keeps the arrays current.
///
/// Write rules:
/// - Inserts and deletes wait for the server, then change memory.
/// - Updates change memory first (see `optimisticUpdate`), then go back on failure.
@MainActor
@Observable
final class DataStore {
  let userID: UUID

  // Extensions in other files write these, so the setters cannot be private.
  // Views must treat them as read-only.
  var lists: [ReminderList] = []
  var reminders: [Reminder] = []
  private(set) var isLoaded = false

  /// The number of updates that wait for the server, for each row id.
  /// Realtime uses it to ignore the echo of an older edit.
  @ObservationIgnored var inFlight: [UUID: Int] = [:]

  @ObservationIgnored let client: SupabaseClient
  @ObservationIgnored let listsRepository: ListsRepository

  init(client: SupabaseClient, userID: UUID) {
    self.client = client
    self.userID = userID
    listsRepository = ListsRepository(client: client)
  }

  /// Reads everything that the user can see. Call it after sign-in and after the
  /// connection returns.
  func load() async throws {
    lists = try await listsRepository.fetchAll()
    isLoaded = true
  }

  // MARK: Lists

  func list(id: UUID) -> ReminderList? {
    lists.first { $0.id == id }
  }

  func isOwner(of list: ReminderList) -> Bool {
    list.ownerID == userID
  }

  func createList(name: String, color: String, icon: String) async throws {
    let list = try await listsRepository.create(name: name, color: color, icon: icon)
    upsert(list, in: \.lists)
  }

  func updateList(_ list: ReminderList) async throws {
    try await optimisticUpdate(\.lists, to: list) {
      try await listsRepository.update(list)
    }
  }

  func deleteList(id: UUID) async throws {
    try await listsRepository.delete(id: id)
    removeList(id: id)
  }

  /// Removes a list and the rows that belong to it. The server does the same by cascade.
  func removeList(id: UUID) {
    lists.removeAll { $0.id == id }
    reminders.removeAll { $0.listID == id }
  }

  // MARK: Shared helpers

  /// A key path to one of the row arrays of the store.
  typealias Rows<Row> = ReferenceWritableKeyPath<DataStore, [Row]>

  /// Inserts the row, or replaces the row with the same id.
  ///
  /// Server responses and Realtime events both use it, so that the same change can
  /// arrive two times with no effect.
  func upsert<Row: Identifiable>(_ row: Row, in keyPath: Rows<Row>) {
    if let index = self[keyPath: keyPath].firstIndex(where: { $0.id == row.id }) {
      self[keyPath: keyPath][index] = row
    } else {
      self[keyPath: keyPath].append(row)
    }
  }

  /// Shows `new` at once, sends it, and goes back to the old row if the server refuses.
  ///
  /// - Parameters:
  ///   - keyPath: The array that holds the row.
  ///   - new: The row with the user's change.
  ///   - send: The server call. It returns the row as the server saved it.
  func optimisticUpdate<Row: Identifiable>(
    _ keyPath: Rows<Row>,
    to new: Row,
    send: () async throws -> Row
  ) async throws where Row.ID == UUID {
    guard let old = self[keyPath: keyPath].first(where: { $0.id == new.id }) else { return }

    upsert(new, in: keyPath)
    inFlight[new.id, default: 0] += 1

    let result: Result<Row, any Error>
    do {
      result = .success(try await send())
    } catch {
      result = .failure(error)
    }

    let remaining = inFlight[new.id, default: 1] - 1
    inFlight[new.id] = remaining > 0 ? remaining : nil

    // A newer edit of the same row is still on its way. Its result decides what the
    // row shows, so this one must not write over it.
    let isLatest = remaining <= 0
    let rowExists = self[keyPath: keyPath].contains { $0.id == new.id }

    switch result {
    case .success(let saved):
      if isLatest, rowExists { upsert(saved, in: keyPath) }
    case .failure(let error):
      if isLatest, rowExists { upsert(old, in: keyPath) }
      throw error
    }
  }
}
