//
//  ContentView.swift
//  RealtimeSample
//
//  Created by Guilherme Souza on 29/10/23.
//

import Realtime
import SwiftUI

struct ContentView: View {
  @State var inserts: [Message] = []
  @State var updates: [Message] = []
  @State var deletes: [Message] = []

  @State var socketStatus: String?
  @State var channelStatus: String?

  @State var publicSchema: RealtimeChannel?

  var body: some View {
    List {
      Section("INSERTS") {
        ForEach(Array(zip(inserts.indices, inserts)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }

      Section("UPDATES") {
        ForEach(Array(zip(updates.indices, updates)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }

      Section("DELETES") {
        ForEach(Array(zip(deletes.indices, deletes)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }
    }
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .leading) {
        Toggle(
          "Toggle Subscription",
          isOn: Binding(get: { publicSchema?.isJoined == true }, set: { _ in toggleSubscription() })
        )
        Text("Socket: \(socketStatus ?? "")")
        Text("Channel: \(channelStatus ?? "")")
      }
      .padding()
      .background(.regularMaterial)
      .padding()
    }
    .onAppear {
      createSubscription()

      socket.connect()
      socket.onOpen {
        socketStatus = "OPEN"
      }
      socket.onClose {
        socketStatus = "CLOSE"
      }
      socket.onError { error, _ in
        socketStatus = "ERROR: \(error.localizedDescription)"
      }
    }
  }

  func createSubscription() {
    publicSchema = socket.channel("public")
      .on("postgres_changes", filter: ChannelFilter(event: "INSERT", schema: "public")) {
        inserts.append($0)
      }
      .on("postgres_changes", filter: ChannelFilter(event: "UPDATE", schema: "public")) {
        updates.append($0)
      }
      .on("postgres_changes", filter: ChannelFilter(event: "DELETE", schema: "public")) {
        deletes.append($0)
      }

    publicSchema?.onError { _ in channelStatus = "ERROR" }
    publicSchema?.onClose { _ in channelStatus = "Closed gracefully" }
    publicSchema?
      .subscribe { state, _ in
        switch state {
        case .subscribed:
          channelStatus = "OK"
        case .closed:
          channelStatus = "CLOSED"
        case .timedOut:
          channelStatus = "Timed out"
        case .channelError:
          channelStatus = "ERROR"
        }
      }
  }

  func toggleSubscription() {
    if publicSchema?.isJoined == true {
      publicSchema?.unsubscribe()
    } else {
      createSubscription()
    }
  }
}

extension Message {
  func stringfiedPayload() -> String {
    do {
      let data = try JSONSerialization.data(
        withJSONObject: rawPayload, options: [.prettyPrinted, .sortedKeys])
      return String(data: data, encoding: .utf8) ?? ""
    } catch {
      return ""
    }
  }
}

#Preview {
  ContentView()
}
