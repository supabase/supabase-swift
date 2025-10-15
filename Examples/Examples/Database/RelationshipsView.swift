//
//  RelationshipsView.swift
//  Examples
//
//  Demonstrates querying related data and joins
//

import SwiftUI

struct RelationshipsView: View {
  @State var todosWithProfiles: [TodoWithProfile] = []
  @State var error: Error?
  @State var isLoading = false

  var body: some View {
    List {
      Section {
        Text("Query related data across tables using foreign key relationships")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Todos with User Info") {
        Button("Load Data") {
          Task {
            await loadTodosWithProfiles()
          }
        }
        .disabled(isLoading)

        if isLoading {
          ProgressView()
        }

        ForEach(todosWithProfiles, id: \.id) { todoWithProfile in
          VStack(alignment: .leading, spacing: 4) {
            Text(todoWithProfile.description)
              .font(.body)

            if let profile = todoWithProfile.profile {
              Text("Created by: \(profile.fullName ?? "Unknown")")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }

      if let error {
        Section {
          ErrorText(error)
        }
      }
    }
    .navigationTitle("Relationships")
    .gitHubSourceLink()
  }

  @MainActor
  func loadTodosWithProfiles() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      todosWithProfiles =
        try await supabase
        .from("todos")
        .select(
          """
            id,
            description,
            is_complete,
            profile:owner_id (
              id,
              username,
              full_name
            )
          """
        )
        .limit(10)
        .execute()
        .value
    } catch {
      self.error = error
    }
  }
}

struct TodoWithProfile: Codable {
  let id: UUID
  let description: String
  let isComplete: Bool
  let profile: ProfileInfo?

  enum CodingKeys: String, CodingKey {
    case id
    case description
    case isComplete = "is_complete"
    case profile
  }
}

struct ProfileInfo: Codable {
  let id: UUID
  let username: String?
  let fullName: String?

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case fullName = "full_name"
  }
}
