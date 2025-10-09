//
//  DatabaseExamplesView.swift
//  Examples
//
//  Demonstrates PostgREST database operations with Supabase
//

import SwiftUI

struct DatabaseExamplesView: View {
  var body: some View {
    List {
      Section {
        Text("Explore database operations using PostgREST")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Section("CRUD Operations") {
        NavigationLink(destination: TodoListView()) {
          ExampleRow(
            title: "Todo List",
            description: "Create, read, update, and delete todos",
            icon: "checklist"
          )
        }

        NavigationLink(destination: FilteringView()) {
          ExampleRow(
            title: "Filtering & Ordering",
            description: "Query with filters and sorting",
            icon: "line.3.horizontal.decrease.circle"
          )
        }
      }

      Section("Advanced Queries") {
        NavigationLink(destination: RPCExamplesView()) {
          ExampleRow(
            title: "RPC Functions",
            description: "Call stored procedures and functions",
            icon: "gearshape.2"
          )
        }

        NavigationLink(destination: AggregationsView()) {
          ExampleRow(
            title: "Aggregations",
            description: "Count, sum, and aggregate data",
            icon: "chart.bar"
          )
        }
      }

      Section("Relationships") {
        NavigationLink(destination: RelationshipsView()) {
          ExampleRow(
            title: "Joins & Relations",
            description: "Query related data across tables",
            icon: "link"
          )
        }
      }
    }
    .navigationTitle("Database")
  }
}

struct ExampleRow: View {
  let title: String
  let description: String
  let icon: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.accentColor)
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}
