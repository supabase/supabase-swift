import Foundation
import Supabase

// Realtime sync. One channel follows every table that the app shows. Row level security
// applies to these events, so each user gets only the changes they can read.
extension DataStore {
  /// Subscribes to changes. Call it before `load()`, so that no change is lost between
  /// the two: an event that arrives while the load runs makes the load read again.
  func startRealtime() async {
    await stopRealtime()

    // Each start has its own topic, so two starts that overlap never share one channel.
    // `client.channel` gives back the open channel when the topic is the same.
    let channel = await client.channel("reminders-sync-\(UUID().uuidString)")
    realtimeChannel = channel
    // Open the streams before `subscribe`, so that the join lists every table.
    let lists = await channel.postgresChanges(of: ReminderList.self, table: "lists")
    let reminders = await channel.postgresChanges(of: Reminder.self, table: "reminders")
    let members = await channel.postgresChanges(table: "list_members")
    let invitations = await channel.postgresChanges(table: "list_invitations")
    let attachments = await channel.postgresChanges(
      of: Attachment.self, table: "reminder_attachments")
    let events = await channel.events()

    do {
      // Returns when the server reports that the Postgres changes are live.
      try await channel.subscribe()
    } catch {
      if realtimeChannel === channel, !Task.isCancelled { self.error = error }
      return
    }

    // A newer start, or a stop, took the place of this one while it joined.
    guard realtimeChannel === channel else { return }
    realtimeTask = Task { [weak self] in
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          for await change in lists { await self?.applyListChange(change) }
        }
        group.addTask {
          for await change in reminders { await self?.applyReminderChange(change) }
        }
        group.addTask {
          for await change in members { await self?.membershipChanged(change) }
        }
        group.addTask {
          for await change in invitations { await self?.invitationsChanged(change) }
        }
        group.addTask {
          for await change in attachments { await self?.applyAttachmentChange(change) }
        }
        group.addTask {
          for await event in events where event == .resubscribed { await self?.rejoined() }
        }
      }
    }
  }

  func stopRealtime() async {
    realtimeTask?.cancel()
    realtimeTask = nil
    if let realtimeChannel {
      await client.removeChannel(realtimeChannel)
    }
    realtimeChannel = nil
  }

  private func applyListChange(_ change: TypedPostgresChange<ReminderList>) {
    switch change.kind {
    case .insert:
      if let list = try? change.row() { upsert(list, in: \.lists) }
    case .update:
      if let list = try? change.row(), !hasUpdateInFlight(list.id) { upsert(list, in: \.lists) }
    case .delete:
      if let id = rowID(in: change.oldRecord) { removeList(id: id) }
    default:
      break
    }
  }

  private func applyReminderChange(_ change: TypedPostgresChange<Reminder>) {
    switch change.kind {
    case .insert:
      if let reminder = try? change.row() { upsert(reminder, in: \.reminders) }
    case .update:
      if let reminder = try? change.row(), !hasUpdateInFlight(reminder.id) {
        upsert(reminder, in: \.reminders)
      }
    case .delete:
      if let id = rowID(in: change.oldRecord) { removeReminder(id: id) }
    default:
      break
    }
  }

  private func applyAttachmentChange(_ change: TypedPostgresChange<Attachment>) {
    switch change.kind {
    case .insert, .update:
      if let attachment = try? change.row() { upsert(attachment, in: \.attachments) }
    case .delete:
      if let id = rowID(in: change.oldRecord), attachments.contains(where: { $0.id == id }) {
        changeCount += 1
        attachments.removeAll { $0.id == id }
      }
    default:
      break
    }
  }

  /// The channel joined again after the socket dropped and came back. Changes made while
  /// it was away never arrive, so everything is read again.
  private func rejoined() async {
    do {
      try await load()
    } catch {
      self.error = error
    }
  }

  /// A person joined or left a list. The set of rows that this user can read may be
  /// different now, so everything is read again.
  ///
  /// Row level security does not apply to delete events: each client gets the delete
  /// events of all users. The app ignores those for lists that it does not show.
  private func membershipChanged(_ change: PostgresChange) async {
    if change.kind == .delete {
      let listID = change.oldRecord?["list_id"]?.stringValue.flatMap(UUID.init(uuidString:))
      guard let listID, list(id: listID) != nil else { return }
    }
    do {
      try await load()
    } catch {
      self.error = error
    }
  }

  /// An invitation row has no list name, so the app reads the invitations again.
  /// As for members, a delete event can be about an invitation of other people.
  private func invitationsChanged(_ change: PostgresChange) async {
    if change.kind == .delete {
      guard let id = rowID(in: change.oldRecord),
        sentInvitations.contains(where: { $0.id == id })
          || incomingInvitations.contains(where: { $0.id == id })
      else { return }
    }
    do {
      try await reloadInvitations()
    } catch {
      self.error = error
    }
  }

  /// True while an update of this row waits for the server.
  ///
  /// The server sends back each change. When the user edits a row two times fast, the
  /// echo of the first edit arrives after the second edit is on screen. Without this
  /// check the row would show the first value again for a moment.
  private func hasUpdateInFlight(_ id: UUID) -> Bool {
    pendingEdits[id] != nil
  }

  /// A delete event has only the primary key of the row.
  private func rowID(in record: PostgresRow?) -> UUID? {
    record?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
  }
}
