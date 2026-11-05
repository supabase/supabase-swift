//
//  LiveQueryView.swift
//  Examples
//
//  Demonstrates the `LiveQuery` observable: the rows of a table, kept in sync with the database
//

@_spi(Experimental) import Supabase
import SwiftUI

struct LiveQueryView: View {
  @State private var todos = LiveQuery(supabase, Todo.self, animation: .default)

  var body: some View {
    List {
      Section {
        Text(
          "LiveQuery fetches the rows, subscribes to changes, and fetches again when the channel joins again"
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section {
        let isLive = todos.isLive
        Label(
          isLive ? "Live" : "Catching up…",
          systemImage: isLive ? "dot.radiowaves.left.and.right" : "arrow.triangle.2.circlepath"
        )
        .foregroundColor(isLive ? .green : .orange)
        .font(.caption)
      }

      if let error = todos.error {
        Section {
          ErrorText(error)
        }
      }

      Section("Todos (\(todos.rows.count))") {
        ForEach(todos.rows) { todo in
          TodoListRow(todo: todo) {}
        }
      }
    }
    .navigationTitle("Live Query")
    .gitHubSourceLink()
    .task {
      // Ends the query and removes its channel when the view goes away.
      await todos.run()
    }
  }
}
