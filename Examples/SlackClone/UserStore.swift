//
//  UserStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class UserStore {
  static let shared = UserStore()

  private(set) var users: [User.ID: User] = [:]
  private(set) var presences: [User.ID: UserPresence] = [:]

  private init() {
    Task {
      let channel = await supabase.channel("public:users")
      let changes = await channel.postgresChanges(of: User.self, table: "users", decoder: decoder)

      let presences = await channel.presenceChanges()

      try await channel.subscribe()

      Task {
        let statusChange = await channel.statusChanges()
        for await _ in statusChange.filter(\.isSubscribed) {
          let userId = try await supabase.auth.session.user.id
          try await channel.track(UserPresence(userId: userId, onlineAt: Date()))
        }
      }

      Task {
        for await change in changes {
          handleChangedUser(change)
        }
      }

      Task {
        for await presence in presences {
          let joins = try presence.decodeJoins(as: UserPresence.self)
          let leaves = try presence.decodeLeaves(as: UserPresence.self)

          for leave in leaves {
            self.presences[leave.userId] = nil
            Logger.main.debug("User \(leave.userId) leaved")
          }

          for join in joins {
            self.presences[join.userId] = join
            Logger.main.debug("User \(join.userId) joined")
          }
        }
      }
    }
  }

  func fetchUser(id: UUID) async throws -> User {
    if let user = users[id] {
      return user
    }

    let user: User =
      try await supabase
      .from("users")
      .select()
      .eq("id", value: id)
      .single()
      .execute()
      .value
    users[user.id] = user
    return user
  }

  private func handleChangedUser(_ change: TypedPostgresChange<User>) {
    do {
      switch change.kind {
      case .insert, .update:
        let user = try change.row()
        users[user.id] = user
      case .delete:
        guard let id = change.oldRecord?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
        else { return }
        users[id] = nil
      default:
        break
      }
    } catch {
      dump(error)
    }
  }
}
