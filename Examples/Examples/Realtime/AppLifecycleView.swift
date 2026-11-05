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
  @State private var socketStatus: RealtimeClientStatus = .disconnected(nil)
  @State private var channelStatus: RealtimeChannelStatus = .unsubscribed
  @State private var heartbeat: HeartbeatEvent?
  @State private var events: [LifecycleEvent] = []

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
        LabeledContent("Heartbeat", value: description(of: heartbeat))
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

  private func observe() async {
    let channel = await supabaseClient.channel(channelName)

    let socketStatuses = await supabaseClient.realtime.statusChanges()
    let channelStatuses = await channel.statusChanges()
    let heartbeats = await supabaseClient.realtime.heartbeats()

    // The statuses must keep showing while `subscribe()` retries or fails, so the streams are
    // iterated next to it, not after it.
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await subscribe(channel) }
      group.addTask { await showSocketStatus(from: socketStatuses) }
      group.addTask { await showChannelStatus(from: channelStatuses) }
      group.addTask { await showHeartbeat(from: heartbeats) }
    }

    await supabaseClient.removeChannel(channel)
  }

  private func subscribe(_ channel: RealtimeChannel) async {
    do {
      try await channel.subscribe()
    } catch {
      if !Task.isCancelled {
        log("Subscribe failed: \(error.localizedDescription)")
      }
    }
  }

  private func showSocketStatus(from statuses: AsyncStream<RealtimeClientStatus>) async {
    for await status in statuses {
      socketStatus = status
      if !status.isConnected {
        heartbeat = nil
      }
      log("Socket → \(description(of: status))")
    }
  }

  private func showChannelStatus(from statuses: AsyncStream<RealtimeChannelStatus>) async {
    for await status in statuses {
      channelStatus = status
      log("Channel → \(description(of: status))")
    }
  }

  private func showHeartbeat(from events: AsyncStream<HeartbeatEvent>) async {
    for await event in events {
      heartbeat = event
    }
  }

  private func log(_ message: String) {
    events.insert(LifecycleEvent(label: message), at: 0)
    if events.count > 50 {
      events.removeLast(events.count - 50)
    }
  }

  private func description(of status: RealtimeClientStatus) -> String {
    switch status {
    case .disconnected(nil): "Disconnected"
    case .disconnected(let error?): "Disconnected: \(error.message)"
    case .connecting(let attempt): "Connecting (attempt \(attempt))"
    case .connected: "Connected"
    case .reconnecting(let attempt, let retryIn, _):
      "Reconnecting (attempt \(attempt + 1) in \(retryIn))"
    }
  }

  private func description(of status: RealtimeChannelStatus) -> String {
    switch status {
    case .unsubscribed: "Unsubscribed"
    case .subscribing(let attempt): "Subscribing (attempt \(attempt))"
    case .subscribed: "Subscribed"
    case .resubscribing(let attempt, let retryIn, _):
      "Resubscribing (attempt \(attempt + 1) in \(retryIn))"
    case .unsubscribing: "Unsubscribing"
    case .failed(let error): "Failed: \(error.message)"
    }
  }

  private func description(of event: HeartbeatEvent?) -> String {
    switch event {
    case nil: "Waiting for the first heartbeat"
    case .sent: "Sent, waiting for the server"
    case .acknowledged(let latency):
      "Acknowledged in \(latency.formatted(.units(allowed: [.milliseconds], width: .abbreviated)))"
    case .timedOut: "Timed out"
    }
  }
}

private struct LifecycleEvent: Identifiable {
  let id = UUID()
  let label: String
  let timestamp = Date()
}
