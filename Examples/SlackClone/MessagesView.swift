//
//  MessagesView.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import Realtime
import Supabase
import SwiftUI

@Observable
@MainActor
final class MessagesViewModel {
  let channel: Channel
  var messages: [Message] = []
  var newMessage = ""

  let api: MessagesAPI

  init(channel: Channel, api: MessagesAPI = MessagesAPIImpl(supabase: supabase)) {
    self.channel = channel
    self.api = api

    supabase.realtime.logger = { print($0) }
  }

  func loadInitialMessages() {
    Task {
      do {
        messages = try await api.fetchAllMessages(for: channel.id)
      } catch {
        dump(error)
      }
    }
  }

  private var realtimeChannelV2: RealtimeChannel?
  private var observationTask: Task<Void, Never>?

  func startObservingNewMessages() {
    realtimeChannelV2 = supabase.realtimeV2.channel("messages:\(channel.id)")

    let changes = realtimeChannelV2!.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "messages",
      filter: "channel_id=eq.\(channel.id)"
    )

    observationTask = Task {
      try! await realtimeChannelV2!.subscribe()

      for await change in changes {
        do {
          switch change {
          case let .insert(record):
            let message = try await self.message(from: record)
            self.messages.append(message)

          case let .update(record):
            let message = try await self.message(from: record)

            if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
              messages[index] = message
            } else {
              messages.append(message)
            }

          case let .delete(oldRecord):
            let id = oldRecord.oldRecord["id"]?.intValue
            self.messages.removeAll { $0.id == id }

          default:
            break
          }
        } catch {
          dump(error)
        }
      }
    }
  }

  func stopObservingMessages() {
    Task {
      do {
        try await realtimeChannelV2?.unsubscribe()
      } catch {
        dump(error)
      }
    }
  }

  func submitNewMessageButtonTapped() {
    Task {
      do {
        try await api.insertMessage(
          NewMessage(
            message: newMessage,
            userId: supabase.auth.session.user.id,
            channelId: channel.id
          )
        )
      } catch {
        dump(error)
      }
    }
  }

  private func message(from record: HasRecord) async throws -> Message {
    struct MessagePayload: Decodable {
      let id: Int
      let message: String
      let insertedAt: Date
      let authorId: UUID
      let channelId: UUID
    }

    let message = try record.decodeRecord() as MessagePayload

    return try await Message(
      id: message.id,
      insertedAt: message.insertedAt,
      message: message.message,
      user: user(for: message.authorId),
      channel: channel
    )
  }

  private var users: [UUID: User] = [:]
  private func user(for id: UUID) async throws -> User {
    if let user = users[id] { return user }

    let user = try await supabase.database.from("users").select().eq("id", value: id).execute()
      .value as User
    users[id] = user
    return user
  }
}

struct MessagesView: View {
  @Bindable var model: MessagesViewModel

  var body: some View {
    List {
      ForEach(model.messages) { message in
        VStack(alignment: .leading) {
          Text(message.user.username)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(message.message)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      ComposeMessageView(text: $model.newMessage) {
        model.submitNewMessageButtonTapped()
      }
      .padding()
    }
    .navigationTitle(model.channel.slug)
    .onAppear {
      model.loadInitialMessages()
      model.startObservingNewMessages()
    }
    .onDisappear {
      model.stopObservingMessages()
    }
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

#Preview {
  MessagesView(model: MessagesViewModel(channel: Channel(
    id: 1,
    slug: "public",
    insertedAt: Date()
  )))
}
