//
//  BroadcastView.swift
//  Examples
//
//  Demonstrates broadcast messaging
//

import Supabase
import SwiftUI

struct BroadcastView: View {
  @State var messages: [ChatMessage] = []
  @State var messageText: String = ""
  @State var channel: RealtimeChannel?
  @State var error: Error?

  var body: some View {
    VStack {
      List {
        Section {
          Text("Send and receive messages in real-time using broadcast")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Section("Messages") {
          ForEach(messages) { message in
            VStack(alignment: .leading, spacing: 4) {
              Text(message.text)
                .font(.body)
              Text(message.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        if let error {
          Section {
            ErrorText(error)
          }
        }
      }

      HStack {
        TextField("Type a message...", text: $messageText)
          .textFieldStyle(.roundedBorder)

        Button("Send") {
          sendMessage()
        }
        .disabled(messageText.isEmpty || channel == nil)
      }
      .padding()
    }
    .navigationTitle("Broadcast")
    .gitHubSourceLink()
    .task {
      await observeMessages()
    }
  }

  func observeMessages() async {
    let channel = await supabaseClient.channel("broadcast-example") {
      $0.broadcast.receiveOwnMessages = true
    }

    let broadcasts = await channel.broadcasts(event: "message")

    do {
      error = nil
      try await channel.subscribe()
      self.channel = channel

      for await broadcast in broadcasts {
        // One malformed message should not end the subscription.
        do {
          messages.append(try broadcast.decode(as: ChatMessage.self))
        } catch {
          self.error = error
        }
      }
    } catch {
      if !Task.isCancelled {
        self.error = error
      }
    }

    self.channel = nil
    await supabaseClient.removeChannel(channel)
  }

  func sendMessage() {
    guard let channel, !messageText.isEmpty else { return }

    let message = ChatMessage(text: messageText)

    Task {
      do {
        try await channel.broadcast(event: "message", payload: message)
        messageText = ""
      } catch {
        self.error = error
      }
    }
  }
}

nonisolated struct ChatMessage: Codable, Identifiable {
  var id: UUID = UUID()
  let text: String
  var timestamp: Date = Date()
}
