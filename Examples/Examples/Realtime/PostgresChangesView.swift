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
  @State var channel: RealtimeChannelV2?
  @State var isSubscribed = false
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text("Listen to database changes in real-time")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        Button(isSubscribed ? "Unsubscribe" : "Subscribe to Changes") {
          if isSubscribed {
            unsubscribe()
          } else {
            subscribe()
          }
        }

        if isSubscribed {
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
    .onDisappear {
      unsubscribe()
    }
  }

  func subscribe() {
    let channel = supabase.channel("postgres-changes-example")

    Task {
      do {
        let insertions = channel.postgresChange(
          InsertAction.self,
          schema: "public",
          table: "todos"
        )

        let updates = channel.postgresChange(
          UpdateAction.self,
          schema: "public",
          table: "todos"
        )

        let deletes = channel.postgresChange(
          DeleteAction.self,
          schema: "public",
          table: "todos"
        )

        try await channel.subscribeWithError()

        self.channel = channel
        isSubscribed = true

        // Handle insertions
        Task {
          for await insertion in insertions {
            await MainActor.run {
              events.insert(
                RealtimeEvent(
                  type: "INSERT",
                  description: insertion.record.description,
                  timestamp: Date()
                ),
                at: 0
              )
            }
          }
        }

        // Handle updates
        Task {
          for await update in updates {
            await MainActor.run {
              events.insert(
                RealtimeEvent(
                  type: "UPDATE",
                  description: update.record.description,
                  timestamp: Date()
                ),
                at: 0
              )
            }
          }
        }

        // Handle deletes
        Task {
          for await _ in deletes {
            await MainActor.run {
              events.insert(
                RealtimeEvent(
                  type: "DELETE",
                  description: "Todo deleted",
                  timestamp: Date()
                ),
                at: 0
              )
            }
          }
        }
      }
    }
  }

  func unsubscribe() {
    Task {
      if let channel {
        await supabase.removeChannel(channel)
      }
      await MainActor.run {
        self.channel = nil
        isSubscribed = false
      }
    }
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
