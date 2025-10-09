//
//  RealtimeExamplesView.swift
//  Examples
//
//  Demonstrates Supabase Realtime features
//

import SwiftUI

struct RealtimeExamplesView: View {
  var body: some View {
    List {
      Section {
        Text(
          "Subscribe to real-time changes in your database and communicate with presence and broadcast"
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Database Changes") {
        NavigationLink(destination: PostgresChangesView()) {
          ExampleRow(
            title: "Postgres Changes",
            description: "Listen to INSERT, UPDATE, DELETE events",
            icon: "antenna.radiowaves.left.and.right"
          )
        }

        NavigationLink(destination: TodoRealtimeView()) {
          ExampleRow(
            title: "Live Todo List",
            description: "Real-time todo updates",
            icon: "checklist"
          )
        }
      }

      Section("Broadcast") {
        NavigationLink(destination: BroadcastView()) {
          ExampleRow(
            title: "Broadcast Messages",
            description: "Send and receive broadcast events",
            icon: "megaphone"
          )
        }
      }

      Section("Presence") {
        NavigationLink(destination: PresenceView()) {
          ExampleRow(
            title: "Presence Tracking",
            description: "Track online users in real-time",
            icon: "person.3"
          )
        }
      }
    }
    .navigationTitle("Realtime")
  }
}
