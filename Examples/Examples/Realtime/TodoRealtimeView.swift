//
//  TodoRealtimeView.swift
//  Examples
//
//  Demonstrates a live updating todo list using Realtime
//

import IdentifiedCollections
import Supabase
import SwiftUI

struct TodoRealtimeView: View {
  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var channel: RealtimeChannelV2?
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text("This list updates automatically when todos change")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Live Todos (\(todos.count))") {
        ForEach(todos) { todo in
          TodoListRow(todo: todo) {}
        }
      }

      Section("Tip") {
        Text(
          "Go to Database > Todo List to create, update, or delete todos and see them update here in real-time"
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }
    }
    .navigationTitle("Live Todo List")
    .gitHubSourceLink()
    .task {
      await loadInitialTodos()
      subscribeToChanges()
    }
    .onDisappear {
      Task {
        if let channel {
          await supabase.removeChannel(channel)
        }
      }
    }
  }

  @MainActor
  func loadInitialTodos() async {
    do {
      error = nil
      todos = try await IdentifiedArrayOf(
        uniqueElements: supabase.from("todos")
          .select()
          .order("created_at", ascending: false)
          .execute()
          .value as [Todo]
      )
    } catch {
      self.error = error
    }
  }

  func subscribeToChanges() {
    let channel = supabase.channel("live-todos")

    Task {
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

      // Handle insertions
      Task {
        for await insertion in insertions {
          try todos.insert(insertion.decodeRecord(decoder: JSONDecoder()), at: 0)
        }
      }

      // Handle updates
      Task {
        for await update in updates {
          let record = try update.decodeRecord(decoder: JSONDecoder()) as Todo
          todos[id: record.id] = record
        }
      }

      // Handle deletes
      Task {
        for await delete in deletes {
          await MainActor.run {
            guard
              let id = delete.oldRecord["id"].flatMap(\.stringValue).flatMap(UUID.init(uuidString:))
            else { return }
            todos.remove(id: id)
          }
        }
      }
    }
  }
}
