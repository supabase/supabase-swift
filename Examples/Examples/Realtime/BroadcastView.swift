//
//  BroadcastView.swift
//  Examples
//
//  Demonstrates broadcast messaging
//

import Supabase
import SwiftUI

struct BroadcastView: View {
  @State var messages: [BroadcastMessage] = []
  @State var messageText: String = ""
  @State var channel: RealtimeChannelV2?
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
        .disabled(messageText.isEmpty)
      }
      .padding()
    }
    .navigationTitle("Broadcast")
    .gitHubSourceLink()
    .task {
      subscribe()
    }
    .onDisappear {
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
  }

  func subscribe() {
    let channel = supabase.channel("broadcast-example")

    Task {
      do {
        let broadcast = channel.broadcastStream(event: "message")

        try await channel.subscribeWithError()
        self.channel = channel

        for await message in broadcast {
          if let payload = try message["payload"]?.decode(as: BroadcastMessage.self) {
            messages.append(payload)
          }
        }
      } catch {
        print(error)
      }
    }
  }

  func sendMessage() {
    guard !messageText.isEmpty else { return }

    Task {
      let message = BroadcastMessage(text: messageText, timestamp: Date())
      try await channel?.broadcast(event: "message", message: message)

      await MainActor.run {
        messageText = ""
      }
    }
  }
}

struct BroadcastMessage: Codable, Identifiable {
  var id: UUID = UUID()
  let text: String
  var timestamp: Date = Date()
}
