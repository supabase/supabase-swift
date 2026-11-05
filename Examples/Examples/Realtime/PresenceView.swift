//
//  PresenceView.swift
//  Examples
//
//  Demonstrates presence tracking
//

import Supabase
import SwiftUI

struct PresenceView: View {
  @Environment(AuthModel.self) var auth
  @State var onlineUsers: [PresenceUser] = []
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text("Track which users are currently online")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Online Users (\(onlineUsers.count))") {
        if onlineUsers.isEmpty {
          Text("No users online")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(onlineUsers) { user in
            HStack {
              Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
              Text(user.username)
            }
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }
    }
    .navigationTitle("Presence")
    .gitHubSourceLink()
    .task {
      guard let userID = auth.user?.id else { return }
      await observePresence(of: userID)
    }
  }

  func observePresence(of userID: UUID) async {
    let user = PresenceUser(id: userID.uuidString, username: "User \(userID.uuidString.prefix(8))")

    // One key per user, so a user signed in on two devices counts once.
    let channel = await supabaseClient.channel("presence-example") {
      $0.presence.key = user.id
    }

    // Presence streams shape the join request, so open them before `subscribe()`.
    let states = await channel.presenceStates()
    let events = await channel.events()

    do {
      error = nil
      try await channel.subscribe()
      try await channel.track(user)

      await withTaskGroup(of: Void.self) { group in
        group.addTask { await trackAgain(user, on: channel, after: events) }
        group.addTask { await showOnlineUsers(in: states) }
      }
    } catch {
      if !Task.isCancelled {
        self.error = error
      }
    }

    await supabaseClient.removeChannel(channel)
  }

  /// The server forgets the tracked payload when the channel joins again.
  func trackAgain(
    _ user: PresenceUser, on channel: RealtimeChannel,
    after events: AsyncStream<RealtimeChannelEvent>
  ) async {
    for await event in events where event == .resubscribed {
      do {
        try await channel.track(user)
      } catch {
        self.error = error
      }
    }
  }

  /// Each state holds everyone who is present, so joins and leaves both show up.
  func showOnlineUsers(in states: AsyncStream<PresenceState>) async {
    for await state in states {
      do {
        onlineUsers = try state.decode(as: PresenceUser.self).values
          .compactMap(\.first)
          .sorted { $0.username < $1.username }
      } catch {
        self.error = error
      }
    }
  }
}

nonisolated struct PresenceUser: Identifiable, Codable {
  let id: String
  let username: String
}
