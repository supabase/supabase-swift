//
//  MessagesView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Realtime
import Supabase
import SwiftUI

struct UserPresence: Codable {
  var userId: UUID
  var onlineAt: Date
}

@MainActor
struct MessagesView: View {
  let store = Store.shared.messages

  let channel: Channel
  @State private var newMessage = ""

  var messages: [Message] {
    store.messages[channel.id, default: []]
  }

  var body: some View {
    List {
      ForEach(messages) { message in
        VStack(alignment: .leading) {
          Text(message.user.username)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(message.message)
        }
      }
    }
    .task {
      await store.loadInitialMessages(channel.id)
    }
    .safeAreaInset(edge: .bottom) {
      ComposeMessageView(text: $newMessage) {
        Task {
          try! await submitNewMessageButtonTapped()
        }
      }
      .padding()
    }
    .navigationTitle(channel.slug)
  }

  private func submitNewMessageButtonTapped() async throws {
    let message = try await NewMessage(
      message: newMessage,
      userId: supabase.auth.session.user.id,
      channelId: channel.id
    )

    try await supabase.database.from("messages").insert(message).execute()
  }
}

struct ComposeMessageView: View {
  @Binding var text: String
  var onSubmit: () -> Void

  var body: some View {
    HStack {
      TextField("Type here", text: $text)
      Button {
        onSubmit()
      } label: {
        Image(systemName: "arrow.up.right.circle")
      }
    }
  }
}
