//
//  PresenceView.swift
//  Examples
//
//  Demonstrates presence tracking
//

import Supabase
import SwiftUI

struct PresenceView: View {
  @Environment(AuthController.self) var auth
  @State var onlineUsers: [PresenceUser] = []
  @State var channel: RealtimeChannel?
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
      await subscribe()
    }
    .onDisappear {
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
  }

  func subscribe() async {
    do {
      let channel = await supabase.channel("presence-example")

      let states = await channel.presenceStates()

      try await channel.subscribe()
      self.channel = channel

      let userId = auth.currentUserID
      let user = PresenceUser(
        id: userId.uuidString,
        username: "User \(userId.uuidString.prefix(8))"
      )

      Task {
        // The server forgets the tracked payload when the channel rejoins.
        for await status in await channel.statusChanges() where status.isSubscribed {
          try await channel.track(user)
        }
      }

      for await state in states {
        onlineUsers = try state.decode(as: PresenceUser.self).values
          .compactMap(\.first)
          .sorted { $0.username < $1.username }
      }
    } catch {
      print("Error: \(error)")
    }
  }
}

nonisolated struct PresenceUser: Identifiable, Codable {
  let id: String
  let username: String
}
