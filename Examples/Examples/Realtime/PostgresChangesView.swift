//
//  PostgresChangesView.swift
//  Examples
//
//  Demonstrates listening to Postgres changes via Realtime
//

import Supabase
import SwiftUI

struct PostgresChangesView: View {
  @State var events: [RealtimeEvent] = []
  @State var isListening = false
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text("Listen to database changes in real-time")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        Button(isListening ? "Unsubscribe" : "Subscribe to Changes") {
          isListening.toggle()
        }

        if isListening {
          Label("Listening for changes...", systemImage: "antenna.radiowaves.left.and.right")
            .foregroundColor(.green)
            .font(.caption)
        }
      }

      Section("Events (\(events.count))") {
        if events.isEmpty {
          Text("No events yet. Try creating, updating, or deleting todos in the Database tab.")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          ForEach(events) { event in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(event.type)
                  .font(.headline)
                  .foregroundColor(event.color)
                Spacer()
                Text(event.timestamp, style: .time)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }

              if let description = event.description {
                Text(description)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }
    }
    .navigationTitle("Postgres Changes")
    .gitHubSourceLink()
    // The task starts when `isListening` turns on, and ends when it turns off or the view goes away.
    .task(id: isListening) {
      guard isListening else { return }
      await observeChanges()
    }
  }

  func observeChanges() async {
    // A new topic for each run, so a quick toggle never meets the channel that the previous run is
    // still removing.
    let channel = await supabase.channel("postgres-changes-example-\(UUID().uuidString)")
    let changes = await channel.postgresChanges(table: "todos")

    do {
      error = nil
      try await channel.subscribe()

      for await change in changes {
        // A delete has no `record`; the old row holds the primary key.
        events.insert(
          RealtimeEvent(
            type: change.kind.rawValue,
            description: (change.record ?? change.oldRecord)?.values.description,
            timestamp: Date()
          ),
          at: 0
        )
        if events.count > 50 {
          events.removeLast(events.count - 50)
        }
      }
    } catch {
      if !Task.isCancelled {
        self.error = error
        isListening = false
      }
    }

    await supabase.removeChannel(channel)
  }
}

struct RealtimeEvent: Identifiable {
  let id = UUID()
  let type: String
  let description: String?
  let timestamp: Date

  var color: Color {
    switch type {
    case "INSERT": return .green
    case "UPDATE": return .blue
    case "DELETE": return .red
    default: return .gray
    }
  }
}
