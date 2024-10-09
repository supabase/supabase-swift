//
//  MessagesView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Realtime
import Supabase
import SwiftUI

struct MessagesView: View {
  let store = Dependencies.shared.messages
  let userStore = Dependencies.shared.users

  let channel: Channel
  @State private var newMessage = ""

  var messages: Messages {
    store.messages[channel.id] ?? .init(sections: [])
  }

  var body: some View {
    List {
      ForEach(messages.sections) { section in
        Section {
          ForEach(section.messages) { message in
            HStack(alignment: .top) {
              Text(message.message)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

              Text(message.insertedAt.formatted())
                .font(.footnote)
            }
          }
        } header: {
          HStack {
            Text(section.author.username)
              .font(.caption)
              .foregroundStyle(.secondary)

            Image(systemName: "circle.fill")
              .foregroundStyle(
                userStore.presences[section.author.id] != nil ? Color.green : Color
                  .red
              )
          }
        }
      }
    }
    .task {
      await store.loadInitialMessages(channel.id)
    }
    .safeAreaInset(edge: .bottom) {
      ComposeMessageView(text: $newMessage) {
        Task {
          await submitNewMessageButtonTapped()
        }
      }
      .padding()
    }
    .navigationTitle(channel.slug)
  }

  private func submitNewMessageButtonTapped() async {
    guard !newMessage.isEmpty else { return }

    do {
      let message = try await NewMessage(
        message: newMessage,
        userId: supabase.auth.session.user.id,
        channelId: channel.id
      )

      try await supabase.from("messages").insert(message).execute()
      newMessage = ""
    } catch {
      dump(error)
    }
  }
}

struct ComposeMessageView: View {
  @Binding var text: String
  var onSubmit: () -> Void

  var body: some View {
    HStack {
      TextField("Type here", text: $text)
        .onSubmit {
          onSubmit()
        }

      Button {
        onSubmit()
      } label: {
        Image(systemName: "arrow.up.right.circle")
      }
    }
  }
}
