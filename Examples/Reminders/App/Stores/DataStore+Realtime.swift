import Foundation
import Supabase

// Realtime sync. One channel follows every table that the app shows. Row level security
// applies to these events, so each user gets only the changes they can read.
extension DataStore {
  /// Subscribes to changes. Call it before `load()`, so that no change is lost between
  /// the two: an event that arrives while the load runs makes the load read again.
  func startRealtime() async {
    await stopRealtime()

    // Each start has its own topic. `client.channel` gives back an open channel that
    // has the same topic, and a channel cannot get new streams after it joins.
    let channel = client.channel("reminders-sync-\(UUID().uuidString)")
    realtimeChannel = channel
    // The streams must exist before `subscribe`: the join message lists them.
    let lists = channel.postgresChange(AnyAction.self, schema: "public", table: "lists")
    let reminders = channel.postgresChange(AnyAction.self, schema: "public", table: "reminders")
    let members = channel.postgresChange(AnyAction.self, schema: "public", table: "list_members")
    let invitations = channel.postgresChange(
      AnyAction.self, schema: "public", table: "list_invitations")
    let attachments = channel.postgresChange(
      AnyAction.self, schema: "public", table: "reminder_attachments")

    do {
      try await channel.subscribeWithError()
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

  private func applyListChange(_ change: AnyAction) {
    switch change {
    case .insert(let action):
      if let list = decode(ReminderList.self, from: action.record) { upsert(list, in: \.lists) }
    case .update(let action):
      if let list = decode(ReminderList.self, from: action.record), !hasUpdateInFlight(list.id) {
        upsert(list, in: \.lists)
      }
    case .delete(let action):
      if let id = rowID(in: action.oldRecord) { removeList(id: id) }
    }
  }

  private func applyReminderChange(_ change: AnyAction) {
    switch change {
    case .insert(let action):
      if let reminder = decode(Reminder.self, from: action.record) {
        upsert(reminder, in: \.reminders)
      }
    case .update(let action):
      if let reminder = decode(Reminder.self, from: action.record),
        !hasUpdateInFlight(reminder.id)
      {
        upsert(reminder, in: \.reminders)
      }
    case .delete(let action):
      if let id = rowID(in: action.oldRecord) { removeReminder(id: id) }
    }
  }

  private func applyAttachmentChange(_ change: AnyAction) {
    switch change {
    case .insert(let action):
      if let attachment = decode(Attachment.self, from: action.record) {
        upsert(attachment, in: \.attachments)
      }
    case .update(let action):
      if let attachment = decode(Attachment.self, from: action.record) {
        upsert(attachment, in: \.attachments)
      }
    case .delete(let action):
      if let id = rowID(in: action.oldRecord), attachments.contains(where: { $0.id == id }) {
        changeCount += 1
        attachments.removeAll { $0.id == id }
      }
    }
  }

  /// A person joined or left a list. The set of rows that this user can read may be
  /// different now, so everything is read again.
  ///
  /// Row level security does not apply to delete events: each client gets the delete
  /// events of all users. The app ignores those for lists that it does not show.
  private func membershipChanged(_ change: AnyAction) async {
    if case .delete(let action) = change {
      let listID = action.oldRecord["list_id"]?.stringValue.flatMap(UUID.init(uuidString:))
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
  private func invitationsChanged(_ change: AnyAction) async {
    if case .delete(let action) = change {
      guard let id = rowID(in: action.oldRecord),
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
    inFlight[id, default: 0] > 0
  }

  private func decode<Row: Decodable>(_ type: Row.Type, from record: [String: AnyJSON]) -> Row? {
    try? record.decode(as: type, decoder: AnyJSON.decoder)
  }

  /// A delete event has only the primary key of the row.
  private func rowID(in record: [String: AnyJSON]) -> UUID? {
    record["id"]?.stringValue.flatMap(UUID.init(uuidString:))
  }
}
