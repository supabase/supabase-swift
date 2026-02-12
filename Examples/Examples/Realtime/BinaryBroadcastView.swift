//
//  BinaryBroadcastView.swift
//  Examples
//
//  Demonstrates binary broadcast messaging using protocol v2
//

import Supabase
import SwiftUI

struct BinaryBroadcastView: View {
  @State var receivedFrames: [BinaryFrame] = []
  @State var inputText: String = ""
  @State var channel: RealtimeChannelV2?
  @State var subscription: RealtimeSubscription?
  @State var error: Error?

  var body: some View {
    VStack {
      List {
        Section {
          Text(
            "Send and receive binary data using protocol 2.0.0 binary frames. "
              + "Text is encoded to UTF-8 bytes before sending."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        Section("Received Frames") {
          if receivedFrames.isEmpty {
            Text("No frames received yet")
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            ForEach(receivedFrames) { frame in
              VStack(alignment: .leading, spacing: 4) {
                Text(frame.decodedText)
                  .font(.body)
                HStack {
                  Text("\(frame.byteCount) bytes")
                  Spacer()
                  Text(frame.timestamp, style: .time)
                }
                .font(.caption)
                .foregroundColor(.secondary)
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

      HStack {
        TextField("Type a message...", text: $inputText)
          .textFieldStyle(.roundedBorder)

        Button("Send") {
          sendBinary()
        }
        .disabled(inputText.isEmpty)
      }
      .padding()
    }
    .navigationTitle("Binary Broadcast")
    .gitHubSourceLink()
    .task {
      await subscribe()
    }
    .onDisappear {
      subscription?.cancel()
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
  }

  func subscribe() async {
    let channel = supabase.channel("binary-broadcast-example") {
      $0.broadcast.receiveOwnBroadcasts = true
    }

    // Use the binary data stream (protocol 2.0.0 feature)
    let dataStream = channel.broadcastDataStream(event: "binary_message")

    do {
      try await channel.subscribeWithError()
      self.channel = channel

      for await data in dataStream {
        let frame = BinaryFrame(
          data: data,
          decodedText: String(data: data, encoding: .utf8) ?? "<non-UTF-8 data>",
          byteCount: data.count,
          timestamp: Date()
        )
        receivedFrames.append(frame)
      }
    } catch {
      self.error = error
    }
  }

  func sendBinary() {
    guard !inputText.isEmpty else { return }

    Task {
      let data = Data(inputText.utf8)
      await channel?.broadcast(event: "binary_message", data: data)

      await MainActor.run {
        inputText = ""
      }
    }
  }
}

struct BinaryFrame: Identifiable {
  let id = UUID()
  let data: Data
  let decodedText: String
  let byteCount: Int
  let timestamp: Date
}
