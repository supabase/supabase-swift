//
//  AppLifecycleView.swift
//  Examples
//
//  Manually verifies `RealtimeClientOptions.handleAppLifecycle`:
//  background the app, bring it back to foreground, and confirm the
//  socket reconnects and the channel re-joins without user intervention.
//

import Supabase
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

struct AppLifecycleView: View {
  @State private var socketStatus: RealtimeClientStatus = .disconnected
  @State private var channelStatus: RealtimeChannelStatus = .unsubscribed
  @State private var events: [LifecycleEvent] = []
  @State private var channel: RealtimeChannelV2?

  private let channelName = "app-lifecycle-example"

  var body: some View {
    List {
      Section {
        Text(
          """
          Background the app (swipe up / lock the device) and wait a few \
          seconds, then return to the foreground. The socket should \
          reconnect and the channel should re-subscribe automatically.
          """
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Current state") {
        LabeledContent("Socket", value: description(of: socketStatus))
        LabeledContent("Channel", value: description(of: channelStatus))
      }

      Section("Events") {
        if events.isEmpty {
          Text("Waiting for events…")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(events) { event in
            VStack(alignment: .leading, spacing: 2) {
              Text(event.label).font(.body)
              Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("App Lifecycle")
    .gitHubSourceLink()
    .task {
      await observe()
    }
    .onDisappear {
      let channel = channel
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
    #if canImport(UIKit)
      .onReceive(
        NotificationCenter.default.publisher(
          for: UIApplication.didEnterBackgroundNotification)
      ) { _ in
        log("App entered background")
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: UIApplication.willEnterForegroundNotification)
      ) { _ in
        log("App will enter foreground")
      }
    #endif
  }

  @MainActor
  private func observe() async {
    let channel = supabase.channel(channelName)
    self.channel = channel

    let socketStatusStream = supabase.realtimeV2.statusChange
    let channelStatusStream = channel.statusChange

    async let socketStream: Void = { @MainActor in
      for await status in socketStatusStream {
        socketStatus = status
        log("Socket → \(description(of: status))")
      }
    }()

    async let channelStream: Void = { @MainActor in
      for await status in channelStatusStream {
        channelStatus = status
        log("Channel → \(description(of: status))")
      }
    }()

    do {
      try await channel.subscribeWithError()
    } catch {
      log("Subscribe failed: \(error.localizedDescription)")
    }

    _ = await (socketStream, channelStream)
  }

  private func log(_ message: String) {
    events.insert(LifecycleEvent(label: message), at: 0)
    if events.count > 50 {
      events.removeLast(events.count - 50)
    }
  }

  private func description(of status: RealtimeClientStatus) -> String {
    switch status {
    case .disconnected: "Disconnected"
    case .connecting: "Connecting"
    case .connected: "Connected"
    }
  }

  private func description(of status: RealtimeChannelStatus) -> String {
    switch status {
    case .unsubscribed: "Unsubscribed"
    case .subscribing: "Subscribing"
    case .subscribed: "Subscribed"
    case .unsubscribing: "Unsubscribing"
    }
  }
}

private struct LifecycleEvent: Identifiable {
  let id = UUID()
  let label: String
  let timestamp = Date()
}
