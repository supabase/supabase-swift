//
//  FilteringView.swift
//  Examples
//
//  Demonstrates filtering and ordering database queries
//

import IdentifiedCollections
import Supabase
import SwiftUI

struct FilteringView: View {
  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var error: Error?
  @State var filterComplete: FilterOption = .all
  @State var sortOrder: SortOption = .newest

  enum FilterOption: String, CaseIterable {
    case all = "All"
    case complete = "Complete"
    case incomplete = "Incomplete"
  }

  enum SortOption: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case alphabetical = "A-Z"
  }

  var body: some View {
    List {
      Section {
        Text("Filter and sort your todos using PostgREST query builders")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Filters") {
        Picker("Filter", selection: $filterComplete) {
          ForEach(FilterOption.allCases, id: \.self) { option in
            Text(option.rawValue).tag(option)
          }
        }
        .pickerStyle(.segmented)

        Picker("Sort", selection: $sortOrder) {
          ForEach(SortOption.allCases, id: \.self) { option in
            Text(option.rawValue).tag(option)
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Results (\(todos.count))") {
        if todos.isEmpty {
          Text("No todos found")
            .foregroundColor(.secondary)
            .font(.caption)
        } else {
          ForEach(todos) { todo in
            VStack(alignment: .leading, spacing: 4) {
              Text(todo.description)
                .font(.body)
              Text(todo.createdAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }

      Section("Code") {
        CodeExample(code: currentQueryCode)
      }
    }
    .navigationTitle("Filtering & Ordering")
    .task(id: filterComplete) {
      await loadTodos()
    }
    .task(id: sortOrder) {
      await loadTodos()
    }
  }

  var currentQueryCode: String {
    var code = "let query = supabase.from(\"todos\")\n  .select()"

    switch filterComplete {
    case .all:
      break
    case .complete:
      code += "\n  .eq(\"is_complete\", value: true)"
    case .incomplete:
      code += "\n  .eq(\"is_complete\", value: false)"
    }

    switch sortOrder {
    case .newest:
      code += "\n  .order(\"created_at\", ascending: false)"
    case .oldest:
      code += "\n  .order(\"created_at\")"
    case .alphabetical:
      code += "\n  .order(\"description\")"
    }

    code += "\n\nlet todos = try await query.execute().value"
    return code
  }

  func loadTodos() async {
    do {
      error = nil

      var query = supabase.from("todos").select()

      // Apply filter
      switch filterComplete {
      case .all:
        break
      case .complete:
        query = query.eq("is_complete", value: true)
      case .incomplete:
        query = query.eq("is_complete", value: false)
      }

      // Apply sorting
      switch sortOrder {
      case .newest:
        query = query.order("created_at", ascending: false) as! PostgrestFilterBuilder
      case .oldest:
        query = query.order("created_at", ascending: true) as! PostgrestFilterBuilder
      case .alphabetical:
        query = query.order("description", ascending: true) as! PostgrestFilterBuilder
      }

      todos = try await IdentifiedArrayOf(
        uniqueElements: query.execute().value as [Todo]
      )
    } catch {
      self.error = error
    }
  }
}

struct CodeExample: View {
  let code: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Swift Code")
        .font(.caption)
        .foregroundColor(.secondary)
      Text(code)
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
  }
}
