//
//  AggregationsView.swift
//  Examples
//
//  Demonstrates aggregation queries (count, sum, etc.)
//

import SwiftUI

struct AggregationsView: View {
  @State var totalTodos: Int?
  @State var completedTodos: Int?
  @State var incompleteTodos: Int?
  @State var error: Error?
  @State var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Use count and aggregation features to analyze your data")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Counts") {
        Button("Load Statistics") {
          Task {
            await loadStatistics()
          }
        }
        .disabled(isLoading)

        if isLoading {
          ProgressView()
        }

        if let totalTodos {
          HStack {
            Label("Total Todos", systemImage: "list.bullet")
            Spacer()
            Text("\(totalTodos)")
              .foregroundColor(.secondary)
          }
        }

        if let completedTodos {
          HStack {
            Label("Completed", systemImage: "checkmark.circle.fill")
              .foregroundColor(.green)
            Spacer()
            Text("\(completedTodos)")
              .foregroundColor(.secondary)
          }
        }

        if let incompleteTodos {
          HStack {
            Label("Incomplete", systemImage: "circle")
              .foregroundColor(.orange)
            Spacer()
            Text("\(incompleteTodos)")
              .foregroundColor(.secondary)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }
    }
    .navigationTitle("Aggregations")
    .gitHubSourceLink()
    .task {
      await loadStatistics()
    }
  }

  @MainActor
  func loadStatistics() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      // Get total count
      let totalResponse =
        try await supabase
        .from("todos")
        .select("*", count: .exact)
        .execute()
      totalTodos = totalResponse.count

      // Get completed count
      let completedResponse =
        try await supabase
        .from("todos")
        .select("*", count: .exact)
        .eq("is_complete", value: true)
        .execute()
      completedTodos = completedResponse.count

      // Get incomplete count
      let incompleteResponse =
        try await supabase
        .from("todos")
        .select("*", count: .exact)
        .eq("is_complete", value: false)
        .execute()
      incompleteTodos = incompleteResponse.count

    } catch {
      self.error = error
    }
  }
}
