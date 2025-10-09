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
  @State var channel: RealtimeChannelV2?
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

      Section("Code Example") {
        CodeExample(
          code: """
            let channel = supabase.channel("presence-example")

            // Track presence
            let presence = channel.presenceStream()

            await channel.subscribe()

            // Track current user
            await channel.track([
              "user_id": userId,
              "username": username
            ])

            // Listen to presence changes
            for await state in presence {
              print("Online users:", state.count)
            }
            """
        )
      }
    }
    .navigationTitle("Presence")
    .task {
      try? await subscribe()
    }
    .onDisappear {
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
  }

  func subscribe() async throws {
    let channel = supabase.channel("presence-example")

    let presence = channel.presenceChange()

    try await channel.subscribeWithError()
    self.channel = channel

    // Track current user
    let userId = auth.currentUserID
    try await channel.track([
      "user_id": userId.uuidString,
      "username": "User \(userId.uuidString.prefix(8))",
    ])

    // Listen to presence changes
    Task {
      for await state in presence {
        // Convert presence state to array of users
        var users: [PresenceUser] = []
        for (_, presence) in state.joins {
          let decoded = try presence.decodeState(as: PresenceUser.self)
          users.append(decoded)
        }
        onlineUsers = users
      }
    }
  }
}

struct PresenceUser: Identifiable, Decodable {
  let id: String
  let username: String
}
