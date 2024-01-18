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
  private(set) var users: [User.ID: User] = [:]

  init() {
    Task {
      let channel = await supabase.realtimeV2.channel("public:users")
      let changes = await channel.postgresChange(AnyAction.self, table: "users")

      await channel.subscribe(blockUntilSubscribed: true)

      for await change in changes {
        handleChangedUser(change)
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
