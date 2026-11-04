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

      let presences = await channel.presenceStates()

      try await channel.subscribe()

      Task {
        let statusChange = await channel.statusChanges()
        for await _ in statusChange.filter(\.isSubscribed) {
          do {
            let userId = try await supabase.auth.session().user.id
            try await channel.track(UserPresence(userId: userId, onlineAt: Date()))
          } catch {
            Logger.main.error("Failed to track presence: \(error.localizedDescription)")
          }
        }
      }

      Task {
        for await change in changes {
          handleChangedUser(change)
        }
      }

      Task {
        for await state in presences {
          let online = try state.decode(as: UserPresence.self).values.compactMap(\.first)
          self.presences = Dictionary(
            online.map { ($0.userId, $0) }, uniquingKeysWith: { _, latest in latest }
          )
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
