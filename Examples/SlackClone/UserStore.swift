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
      let channel = await supabase.realtime.channel("public:users")
      let changes = await channel.postgresChange(AnyAction.self, table: "users")

      let presences = await channel.presenceChange()

      await channel.subscribe()

      Task {
        let statusChange = await channel.statusChange
        for await _ in statusChange.filter({ $0 == .subscribed }) {
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

          for join in joins {
            self.presences[join.userId] = join
            Logger.main.debug("User \(join.userId) joined")
          }

          for leave in leaves {
            self.presences[leave.userId] = nil
            Logger.main.debug("User \(leave.userId) leaved")
          }
        }
      }
    }
  }

  func fetchUser(id: UUID) async throws -> User {
    if let user = users[id] {
      return user
    }

    let user: User = try await supabase.database
      .from("users")
      .select()
      .eq("id", value: id)
      .single()
      .execute()
      .value
    users[user.id] = user
    return user
  }

  private func handleChangedUser(_ action: AnyAction) {
    do {
      switch action {
      case let .insert(action):
        let user = try action.decodeRecord(decoder: decoder) as User
        users[user.id] = user
      case let .update(action):
        let user = try action.decodeRecord(decoder: decoder) as User
        users[user.id] = user
      case let .delete(action):
        guard let id = action.oldRecord["id"]?.stringValue else { return }
        users[UUID(uuidString: id)!] = nil
      default:
        break
      }
    } catch {
      dump(error)
    }
  }
}
