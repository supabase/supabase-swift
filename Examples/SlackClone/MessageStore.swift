//
//  MessageStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import IdentifiedCollections
import Supabase
import SupabaseSwiftMacros

struct Messages {
  private(set) var sections: [Section]

  struct Section: Hashable, Identifiable {
    var id: AnyHashable { self }

    var author: User
    var messages: IdentifiedArrayOf<MessageWithDetails>
  }

  init(sections: [Section]) {
    self.sections = sections

    for (index, section) in sections.enumerated() {
      for message in section.messages {
        messageToSectionLookupTable[message.id] = index
      }
    }
  }

  private var messageToSectionLookupTable: [MessageWithDetails.ID: Int] = [:]

  mutating func appendOrUpdate(_ message: MessageWithDetails) {
    if let sectionIndex = messageToSectionLookupTable[message.id],
      let messageIndex = sections[sectionIndex].messages
        .firstIndex(where: { $0.id == message.id })
    {
      sections[sectionIndex].messages[messageIndex] = message
    } else {
      append(message)
    }
  }

  mutating func remove(id: MessageWithDetails.ID) {
    if let index = messageToSectionLookupTable[id] {
      sections[index].messages.remove(id: id)
      messageToSectionLookupTable[id] = nil
      if sections[index].messages.isEmpty {
        sections.remove(at: index)
        rebuildLookupTable()
      }
    }
  }

  private mutating func append(_ message: MessageWithDetails) {
    if var section = sections.last, section.author.id == message.user.id {
      section.messages.append(message)
      sections[sections.endIndex - 1] = section
    } else {
      let section = Section(author: message.user, messages: [message])
      sections.append(section)
    }

    messageToSectionLookupTable[message.id] = sections.endIndex - 1
  }

  private mutating func rebuildLookupTable() {
    messageToSectionLookupTable = [:]

    for (index, section) in sections.enumerated() {
      for message in section.messages {
        messageToSectionLookupTable[message.id] = index
      }
    }
  }
}

extension Messages {
  init(_ messages: [MessageWithDetails]) {
    self.init(sections: [])

    for message in messages {
      append(message)
    }
  }
}

@MainActor
@Observable
final class MessageStore {
  static let shared = MessageStore()

  private(set) var messages: [Channel.ID: Messages] = [:]

  struct Section {
    var author: User
    var messages: [MessageWithDetails]
  }

  var users: UserStore { Dependencies.shared.users }
  var channel: ChannelStore { Dependencies.shared.channel }

  private init() {
    Task {
      let channel = supabase.channel("public:messages")

      let insertions = channel.postgresChange(InsertAction.self, table: "messages")
      let updates = channel.postgresChange(UpdateAction.self, table: "messages")
      let deletions = channel.postgresChange(DeleteAction.self, table: "messages")

      try await channel.subscribeWithError()

      Task {
        for await insertion in insertions {
          await handleInsertedOrUpdatedMessage(insertion)
        }
      }

      Task {
        for await update in updates {
          await handleInsertedOrUpdatedMessage(update)
        }
      }

      Task {
        for await delete in deletions {
          handleDeletedMessage(delete)
        }
      }
    }
  }

  func loadInitialMessages(_ channelId: Channel.ID) async {
    do {
      let allMessages = try await fetchMessages(channelId)
      messages[channelId] = Messages(allMessages)
    } catch {
      dump(error)
    }
  }

  func removeMessages(for channel: Channel.ID) {
    messages[channel] = nil
  }

  private func handleInsertedOrUpdatedMessage(_ action: HasRecord) async {
    do {
      let payload = try action.decodeRecord(decoder: decoder) as Message
      let user = try await users.fetchUser(id: payload.userId)
      let channel = try await self.channel.fetchChannel(id: payload.channelId)
      let message = MessageWithDetails(
        id: payload.id,
        insertedAt: payload.insertedAt,
        message: payload.message,
        user: user,
        channel: channel
      )

      var channelMessages = messages[payload.channelId] ?? Messages(sections: [])
      channelMessages.appendOrUpdate(message)
      messages[payload.channelId] = channelMessages
    } catch {
      dump(error)
    }
  }

  private func handleDeletedMessage(_ action: DeleteAction) {
    guard let id = action.oldRecord["id"]?.intValue else {
      return
    }

    for (channel, var messages) in messages {
      messages.remove(id: id)
      self.messages[channel] = messages
    }
  }

  /// Fetch all messages joined with their author and channel.
  private func fetchMessages(_ channelId: Channel.ID) async throws -> [MessageWithDetails] {
    try await supabase
      .from(Message.self)
      .select(MessageWithDetails.self)
      .eq(\.channelId, value: channelId)
      .order(\.insertedAt, ascending: true)
      .execute()
      .value
  }
}
