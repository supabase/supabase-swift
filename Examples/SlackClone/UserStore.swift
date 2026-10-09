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
}
