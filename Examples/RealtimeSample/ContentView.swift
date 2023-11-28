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
  @Published var isJoined: Bool = false

  func createSubscription() async {
    await supabase.realtime.connect()

    publicSchema = await supabase.realtime.channel("public")
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "INSERT", schema: "public")
      ) { [weak self] message in
        await MainActor.run { [weak self] in
          self?.inserts.append(message)
        }
      }
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "UPDATE", schema: "public")
      ) { [weak self] message in
        await MainActor.run { [weak self] in
          self?.updates.append(message)
        }
      }
      .on(
        "postgres_changes",
        filter: ChannelFilter(event: "DELETE", schema: "public")
      ) { [weak self] message in
        await MainActor.run { [weak self] in
          self?.deletes.append(message)
        }
      }

    await publicSchema?.onError { @MainActor [weak self] _ in self?.channelStatus = "ERROR" }
    await publicSchema?
      .onClose { @MainActor [weak self] _ in self?.channelStatus = "Closed gracefully" }
    await publicSchema?
      .subscribe { @MainActor [weak self] state, _ in
        self?.isJoined = await self?.publicSchema?.isJoined == true
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

    await supabase.realtime.connect()
    await supabase.realtime.onOpen { @MainActor [weak self] in
      self?.socketStatus = "OPEN"
    }
    await supabase.realtime.onClose { [weak self] _, _ in
      await MainActor.run { [weak self] in
        self?.socketStatus = "CLOSE"
      }
    }
    await supabase.realtime.onError { @MainActor [weak self] error, _ in
      self?.socketStatus = "ERROR: \(error.localizedDescription)"
    }
  }

  func toggleSubscription() async {
    if await publicSchema?.isJoined == true {
      await publicSchema?.unsubscribe()
    } else {
      await createSubscription()
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
            get: { model.isJoined },
            set: { _ in
              Task {
                await model.toggleSubscription()
              }
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
    .task {
      await model.createSubscription()
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
