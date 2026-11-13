import Foundation
import Observation
import Supabase
import UIKit

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
  var members: [ListMember] = []
  var profiles: [Profile] = []
  var attachments: [Attachment] = []
  /// Invitations of the lists that the user owns.
  var sentInvitations: [Invitation] = []
  /// Pending invitations for the user.
  var incomingInvitations: [IncomingInvitation] = []
  private(set) var isLoaded = false

  /// The last error of a write that a view started with `run`. The root view shows it.
  var error: (any Error)?

  /// The number of updates that wait for the server, for each row id.
  /// Realtime uses it to ignore the echo of an older edit.
  @ObservationIgnored var inFlight: [UUID: Int] = [:]
  /// Goes up each time a server response or a Realtime event changes a row array.
  /// `load()` uses it to see that its result is older than what is on screen.
  @ObservationIgnored var changeCount = 0
  @ObservationIgnored private var loadCount = 0

  @ObservationIgnored let client: SupabaseClient
  @ObservationIgnored var realtimeChannel: RealtimeChannel?
  @ObservationIgnored var realtimeTask: Task<Void, Never>?
  @ObservationIgnored let listsRepository: ListsRepository
  @ObservationIgnored let remindersRepository: RemindersRepository
  @ObservationIgnored let sharingRepository: SharingRepository
  @ObservationIgnored let attachmentsRepository: AttachmentsRepository
  /// Downloaded images by Storage path. The system empties it when memory is low.
  @ObservationIgnored let imageCache = NSCache<NSString, UIImage>()

  init(client: SupabaseClient, userID: UUID) {
    self.client = client
    self.userID = userID
    listsRepository = ListsRepository(client: client)
    remindersRepository = RemindersRepository(client: client)
    sharingRepository = SharingRepository(client: client)
    attachmentsRepository = AttachmentsRepository(client: client)
  }

  /// Reads everything that the user can see. Call it after sign-in and after the
  /// connection returns.
  ///
  /// The result replaces the row arrays, so it must not be older than they are:
  /// - If a newer `load()` started, this one stops. The newer one gives the result.
  /// - If a write or a Realtime event changed a row while the requests ran, the result
  ///   can be from before that change. The load then reads again.
  func load() async throws {
    loadCount += 1
    let thisLoad = loadCount
    let maxAttempts = 3

    for attempt in 1...maxAttempts {
      let changesAtStart = changeCount

      async let lists = listsRepository.fetchAll()
      async let reminders = remindersRepository.fetchAll()
      async let members = sharingRepository.fetchMembers()
      async let profiles = sharingRepository.fetchProfiles()
      async let sent = sharingRepository.fetchSentInvitations(ownerID: userID)
      async let incoming = sharingRepository.fetchIncoming()
      async let attachments = attachmentsRepository.fetchAll()
      let result = try await (lists, reminders, members, profiles, sent, incoming, attachments)

      guard thisLoad == loadCount else { return }
      if changeCount != changesAtStart, attempt < maxAttempts { continue }

      (self.lists, self.reminders, self.members, self.profiles) =
        (result.0, result.1, result.2, result.3)
      (sentInvitations, incomingInvitations, self.attachments) = (result.4, result.5, result.6)
      isLoaded = true
      return
    }
  }

  /// Starts a write and shows its error, if any, in the root alert.
  ///
  /// Use it for a write that outlives the view that starts it, for example an update
  /// from a sheet that closes at once.
  func run(_ operation: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await operation()
      } catch {
        self.error = error
      }
    }
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
    try await deleteFiles(ofReminders: Set(reminders.filter { $0.listID == id }.map(\.id)))
    try await listsRepository.delete(id: id)
    removeList(id: id)
  }

  /// Removes a list and the rows that belong to it. The server does the same by cascade.
  func removeList(id: UUID) {
    let reminderIDs = Set(reminders.filter { $0.listID == id }.map(\.id))
    changeCount += 1
    lists.removeAll { $0.id == id }
    reminders.removeAll { $0.listID == id }
    attachments.removeAll { reminderIDs.contains($0.reminderID) }
  }

  // MARK: Reminders

  /// The reminders of a list in the order of creation.
  func reminders(in listID: UUID, includeCompleted: Bool) -> [Reminder] {
    reminders.filter { $0.listID == listID && (includeCompleted || !$0.isCompleted) }
  }

  func createReminder(
    title: String,
    listID: UUID,
    dueAt: Date? = nil,
    isFlagged: Bool = false
  ) async throws {
    let reminder = try await remindersRepository.create(
      title: title,
      listID: listID,
      dueAt: dueAt,
      isFlagged: isFlagged
    )
    upsert(reminder, in: \.reminders)
  }

  func updateReminder(_ reminder: Reminder) async throws {
    try await optimisticUpdate(\.reminders, to: reminder) {
      try await remindersRepository.update(reminder)
    }
  }

  func toggleCompleted(id: UUID) async throws {
    guard var reminder = reminders.first(where: { $0.id == id }) else { return }
    reminder.completedAt = reminder.isCompleted ? nil : .now
    try await updateReminder(reminder)
  }

  func deleteReminder(id: UUID) async throws {
    try await deleteFiles(ofReminders: [id])
    try await remindersRepository.delete(id: id)
    removeReminder(id: id)
  }

  /// Removes a reminder and its attachment rows. The server does the same by cascade.
  func removeReminder(id: UUID) {
    changeCount += 1
    reminders.removeAll { $0.id == id }
    attachments.removeAll { $0.reminderID == id }
  }

  // MARK: Shared helpers

  /// A key path to one of the row arrays of the store.
  typealias Rows<Row> = ReferenceWritableKeyPath<DataStore, [Row]>

  /// Inserts the row, or replaces the row with the same id.
  ///
  /// Server responses and Realtime events both use it, so that the same change can
  /// arrive two times with no effect.
  func upsert<Row: Identifiable>(_ row: Row, in keyPath: Rows<Row>) {
    changeCount += 1
    if let index = self[keyPath: keyPath].firstIndex(where: { $0.id == row.id }) {
      self[keyPath: keyPath][index] = row
    } else {
      self[keyPath: keyPath].append(row)
    }
  }

  /// Shows `new` at once, sends it, and goes back to the old row if the server refuses.
  ///
  /// If the server finds no row, the user has no access to the row now: a person
  /// deleted it, or moved it to a list that this user cannot read. Realtime sends no
  /// event for such a move. The row then leaves the array, and there is no error.
  ///
  /// - Parameters:
  ///   - keyPath: The array that holds the row.
  ///   - new: The row with the user's change.
  ///   - send: The server call. It returns the row as the server saved it.
  /// - Throws: The error of `send`, after the old row is back in the array.
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
    case .failure(let error as PostgrestError) where error.code == "PGRST116":
      // `.single()` got 0 rows.
      changeCount += 1
      self[keyPath: keyPath].removeAll { $0.id == new.id }
    case .failure(let error):
      if isLatest, rowExists { upsert(old, in: keyPath) }
      throw error
    }
  }
}
