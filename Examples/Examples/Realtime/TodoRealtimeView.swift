//
//  TodoRealtimeView.swift
//  Examples
//
//  Demonstrates a live updating todo list using Realtime
//

import IdentifiedCollections
@_spi(Experimental) import Supabase
import SwiftUI

struct TodoRealtimeView: View {
  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var error: Error?

  var body: some View {
    List {
      Section {
        Text(
          "This list updates automatically when todos change. It does not recover changes missed while the channel was away: see Resubscribe or Live Query."
        )
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
      await observeTodos()
    }
  }

  func observeTodos() async {
    let channel = await supabaseClient.channel("live-todos")
    let changes = await channel.postgresChanges(of: Todo.self)

    do {
      error = nil
      try await channel.subscribe()
      // Fetch after the join, so a change made in between reaches the stream.
      do {
        todos = try await .fetchTodos()
      } catch {
        // The stream still delivers changes, so a failed fetch does not end the screen.
        self.error = error
      }
      for await change in changes {
        do {
          try todos.apply(change)
        } catch {
          self.error = error
        }
      }
    } catch {
      // Leaving the view cancels the task, and that is not an error to show.
      if !Task.isCancelled {
        self.error = error
      }
    }

    await supabaseClient.removeChannel(channel)
  }
}
