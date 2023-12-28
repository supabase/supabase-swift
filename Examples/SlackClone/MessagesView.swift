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

  let api: MessagesAPI

  init(channel: Channel, api: MessagesAPI = MessagesAPIImpl(supabase: supabase)) {
    self.channel = channel
    self.api = api
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

  private var realtimeChannel: _RealtimeChannel?
  func startObservingNewMessages() {
    realtimeChannel = supabase.realtimeV2.channel("messages:\(channel.id)")

    let changes = realtimeChannel!.postgresChange(
      .all,
      table: "messages",
      filter: "channel_id=eq.\(channel.id)"
    )

    Task {
      try! await realtimeChannel!.subscribe()

      for await change in changes {
        do {
          switch change.action {
          case let .insert(record):
            let message = try await self.message(from: record)
            self.messages.append(message)

          case let .update(record, _):
            let message = try await self.message(from: record)

            if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
              messages[index] = message
            } else {
              messages.append(message)
            }

          case let .delete(oldRecord):
            let id = oldRecord["id"]?.intValue
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
        try await realtimeChannel?.unsubscribe()
      } catch {
        dump(error)
      }
    }
  }

  private func message(from payload: [String: AnyJSON]) async throws -> Message {
    struct MessagePayload: Decodable {
      let id: Int
      let message: String
      let insertedAt: Date
      let authorId: UUID
      let channelId: UUID
    }

    let message = try payload.decode(MessagePayload.self)

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
  let model: MessagesViewModel

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

#Preview {
  MessagesView(model: MessagesViewModel(channel: Channel(
    id: 1,
    slug: "public",
    insertedAt: Date()
  )))
}
