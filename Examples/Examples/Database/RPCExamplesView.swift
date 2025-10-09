//
//  RPCExamplesView.swift
//  Examples
//
//  Demonstrates calling Remote Procedure Calls (stored functions)
//

import SwiftUI

struct RPCExamplesView: View {
  @State var name: String = "World"
  @State var result: String?
  @State var userStats: UserStats?
  @State var error: Error?
  @State var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Call PostgreSQL functions using RPC (Remote Procedure Call)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Simple RPC") {
        TextField("Name", text: $name)
        Button("Call hello_world()") {
          Task {
            await callHelloWorld()
          }
        }

        if let result {
          Text(result)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Section("RPC with Complex Return") {
        Button("Get User Statistics") {
          Task {
            await getUserStats()
          }
        }
        .disabled(isLoading)

        if isLoading {
          ProgressView()
        }

        if let stats = userStats {
          VStack(alignment: .leading, spacing: 8) {
            StatsRow(label: "Total Todos", value: "\(stats.todoCount)")
            StatsRow(label: "Total Messages", value: "\(stats.messageCount)")
            if let lastActivity = stats.lastActivity {
              StatsRow(label: "Last Activity", value: lastActivity, style: .relative)
            }
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }

      Section("Code Examples") {
        CodeExample(
          code: """
            // Simple RPC call
            struct HelloWorldResponse: Codable {
              let message: String
              let timestamp: Date
            }

            let response: HelloWorldResponse = try await supabase
              .rpc("hello_world", params: ["name": "\(name)"])
              .single()
              .execute()
              .value
            """)

        CodeExample(
          code: """
            // RPC with complex return
            struct UserStats: Codable {
              let userId: UUID
              let todoCount: Int
              let messageCount: Int
              let lastActivity: Date?
            }

            let stats: [UserStats] = try await supabase
              .rpc("get_user_stats")
              .execute()
              .value
            """)
      }
    }
    .navigationTitle("RPC Functions")
  }

  @MainActor
  func callHelloWorld() async {
    do {
      error = nil
      let response: HelloWorldResponse =
        try await supabase
        .rpc("hello_world", params: ["name": name])
        .single()
        .execute()
        .value
      result = response.message
    } catch {
      self.error = error
    }
  }

  @MainActor
  func getUserStats() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      let stats: [UserStats] =
        try await supabase
        .rpc("get_user_stats")
        .execute()
        .value

      userStats = stats.first
    } catch {
      self.error = error
    }
  }
}

struct HelloWorldResponse: Codable {
  let message: String
  let timestamp: Date
}

struct UserStats: Codable {
  let userId: UUID
  let todoCount: Int
  let messageCount: Int
  let lastActivity: Date?

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case todoCount = "todo_count"
    case messageCount = "message_count"
    case lastActivity = "last_activity"
  }
}

struct StatsRow: View {
  let label: String
  let value: String
  var style: Text.DateStyle?

  init(label: String, value: String) {
    self.label = label
    self.value = value
    self.style = nil
  }

  init(label: String, value: Date, style: Text.DateStyle) {
    self.label = label
    self.value = ""
    self.style = style
  }

  var body: some View {
    HStack {
      Text(label)
      Spacer()
      if let style {
        Text(Date(), style: style)
          .foregroundColor(.secondary)
      } else {
        Text(value)
          .foregroundColor(.secondary)
      }
    }
  }
}
