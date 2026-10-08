//
//  MessageStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import IdentifiedCollections
import Supabase

struct Messages {
  private(set) var sections: [Section]

  struct Section: Hashable, Identifiable {
    var id: AnyHashable { self }

    var author: User
    var messages: IdentifiedArrayOf<Message>
  }

  init(sections: [Section]) {
    self.sections = sections

    for (index, section) in sections.enumerated() {
      for message in section.messages {
        messageToSectionLookupTable[message.id] = index
      }
    }
  }

  private var messageToSectionLookupTable: [Message.ID: Int] = [:]

  mutating func appendOrUpdate(_ message: Message) {
    if let sectionIndex = messageToSectionLookupTable[message.id],
      let messageIndex = sections[sectionIndex].messages
        .firstIndex(where: { $0.id == message.id })
    {
      sections[sectionIndex].messages[messageIndex] = message
    } else {
      append(message)
    }
  }

  mutating func remove(id: Message.ID) {
    if let index = messageToSectionLookupTable[id] {
      sections[index].messages.remove(id: id)
      messageToSectionLookupTable[id] = nil
      if sections[index].messages.isEmpty {
        sections.remove(at: index)
        rebuildLookupTable()
      }
    }
  }

  private mutating func append(_ message: Message) {
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
  init(_ messages: [Message]) {
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
    var messages: [Message]
  }

  func loadInitialMessages(_ channelId: Channel.ID) async {
    do {
      let allMessages = try await fetchMessages(channelId)
      messages[channelId] = Messages(allMessages)
    } catch {
      dump(error)
    }
  }

  /// Fetch all messages and their authors.
  private func fetchMessages(_ channelId: Channel.ID) async throws -> [Message] {
    try await supabase
      .from("messages")
      .select("*,user:user_id(*),channel:channel_id(*)")
      .eq("channel_id", value: channelId)
      .order("inserted_at", ascending: true)
      .execute()
      .value
  }
}
