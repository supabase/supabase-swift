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
      let changes = await channel.postgresChanges(AnyAction.self, table: "users")

      let presences = await channel.presenceStates()

      try await channel.subscribe()

      Task {
        let statusChange = await channel.statusChanges()
        for await _ in statusChange.filter(\.isSubscribed) {
          do {
            let userId = try await supabase.auth.session.user.id
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

  private func handleChangedUser(_ action: AnyAction) {
    do {
      switch action {
      case .insert(let action):
        let user = try action.decodeRecord(decoder: decoder) as User
        users[user.id] = user
      case .update(let action):
        let user = try action.decodeRecord(decoder: decoder) as User
        users[user.id] = user
      case .delete(let action):
        guard let id = action.oldRecord["id"]?.stringValue else { return }
        users[UUID(uuidString: id)!] = nil
      }
    } catch {
      dump(error)
    }
  }
}
