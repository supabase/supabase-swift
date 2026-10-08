//
//  UserStore.swift
//  SlackClone
//
//  Created by Guilherme Souza on 18/01/24.
//

import Foundation
import Supabase

@MainActor
@Observable
final class UserStore {
  static let shared = UserStore()

  private(set) var users: [User.ID: User] = [:]
  private(set) var presences: [User.ID: UserPresence] = [:]

  private init() {
    Task {
      let channel = supabase.channel("public:users")
      let changes = channel.postgresChanges(of: User.self, table: "users", decoder: decoder)
      let presenceStates = channel.presence.states

      do {
        try await channel.subscribe()
        // The SDK tracks this payload again after every rejoin.
        let userId = try await supabase.auth.session.user.id
        try await channel.presence.track(UserPresence(userId: userId, onlineAt: Date()))
      } catch {
        dump(error)
        return
      }

      Task {
        for await change in changes {
          handleChangedUser(change)
        }
      }

      for await state in presenceStates {
        let online = (try? state.decode(as: UserPresence.self)) ?? [:]
        presences = Dictionary(
          online.values.joined().map { ($0.userId, $0) }, uniquingKeysWith: { $1 })
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
    switch change.kind {
    case .insert, .update:
      do {
        let user = try change.row()
        users[user.id] = user
      } catch {
        dump(error)
      }
    case .delete:
      guard let id = change.oldRecord?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
      else { return }
      users[id] = nil
    }
  }
}
