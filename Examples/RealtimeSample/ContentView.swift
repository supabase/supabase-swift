//
//  ContentView.swift
//  RealtimeSample
//
//  Created by Guilherme Souza on 29/10/23.
//

import Realtime
import SwiftUI

@MainActor
final class ViewModel: ObservableObject {
  @Published var inserts: [Message] = []
  @Published var updates: [Message] = []
  @Published var deletes: [Message] = []

  @Published var socketStatus: String?
  @Published var channelStatus: String?

  @Published var publicSchema: RealtimeChannel?

  func createSubscription() {
    supabase.realtime.connect()

    publicSchema = supabase.realtime.channel("public")
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "INSERT", schema: "public")
      ) { [weak self] message in
        self?.inserts.append(message)
      }
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "UPDATE", schema: "public")
      ) { [weak self] message in
        self?.updates.append(message)
      }
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "DELETE", schema: "public")
      ) { [weak self] message in
        self?.deletes.append(message)
      }

    publicSchema?.onError { [weak self] _ in
      self?.channelStatus = "ERROR"
    }
    publicSchema?.onClose { [weak self] _ in
      self?.channelStatus = "Closed gracefully"
    }
    publicSchema?
      .subscribe { [weak self] state, _ in
        switch state {
        case .subscribed:
          self?.channelStatus = "OK"
        case .closed:
          self?.channelStatus = "CLOSED"
        case .timedOut:
          self?.channelStatus = "Timed out"
        case .channelError:
          self?.channelStatus = "ERROR"
        }
      }

    supabase.realtime.connect()
    supabase.realtime.onOpen { [weak self] in
      self?.socketStatus = "OPEN"
    }
    supabase.realtime.onClose { [weak self] _, _ in
      self?.socketStatus = "CLOSE"
    }
    supabase.realtime.onError { [weak self] error, _ in
      self?.socketStatus = "ERROR: \(error.localizedDescription)"
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

struct ContentView: View {
  @StateObject var model = ViewModel()

  var body: some View {
    List {
      Section("INSERTS") {
        ForEach(Array(zip(model.inserts.indices, model.inserts)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }

      Section("UPDATES") {
        ForEach(Array(zip(model.updates.indices, model.updates)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }

      Section("DELETES") {
        ForEach(Array(zip(model.deletes.indices, model.deletes)), id: \.0) { _, message in
          Text(message.stringfiedPayload())
        }
      }
    }
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .leading) {
        Toggle(
          "Toggle Subscription",
          isOn: Binding(
            get: { model.publicSchema?.isJoined == true },
            set: { _ in
              model.toggleSubscription()
            }
          )
        )
        Text("Socket: \(model.socketStatus ?? "")")
        Text("Channel: \(model.channelStatus ?? "")")
      }
      .padding()
      .background(.regularMaterial)
      .padding()
    }
    .onAppear {
      model.createSubscription()
    }
  }
}

extension Message {
  func stringfiedPayload() -> String {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      return String(data: data, encoding: .utf8) ?? ""
    } catch {
      return ""
    }
  }
}

#if swift(>=5.9)
  #Preview {
    ContentView()
  }
#endif
