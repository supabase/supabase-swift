//
//  AuthAdminClient+UserSequence.swift
//  Auth
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation

extension AuthAdminClient {
  /// Every user in the project, as an `AsyncSequence` that walks the pages for you.
  ///
  /// ``listUsers(page:perPage:)`` hands back one page and a ``UserPage/nextPage`` number to
  /// follow. This wraps that loop:
  ///
  /// ```swift
  /// for try await user in admin.users() {
  ///   print(user.email ?? user.id.uuidString)
  /// }
  /// ```
  ///
  /// A page is fetched only when the previous one runs out, so a caller that stops early —
  /// `break`, `prefix(_:)`, `first(where:)` — never pays for the pages it did not read.
  ///
  /// - Parameter perPage: Users per request. `nil` leaves the page size to the server.
  /// - Returns: A sequence of every user, in the order the server returns them.
  public func users(perPage: Int? = nil) -> UserSequence {
    UserSequence(admin: self, perPage: perPage)
  }

  /// An `AsyncSequence` over every user in the project, fetched one page at a time.
  ///
  /// Create one with ``AuthAdminClient/users(perPage:)``.
  public struct UserSequence: AsyncSequence, Sendable {
    public typealias Element = User

    let admin: AuthAdminClient
    let perPage: Int?

    public struct AsyncIterator: AsyncIteratorProtocol {
      let admin: AuthAdminClient
      let perPage: Int?

      /// Users from the most recent page that the caller has not consumed yet.
      private var buffer: ArraySlice<User> = []
      /// The page to request next, or `nil` on the first call (the server picks page one).
      private var nextPage: Int?
      /// Set once the server stops advertising a `next` link.
      private var exhausted = false

      init(admin: AuthAdminClient, perPage: Int?) {
        self.admin = admin
        self.perPage = perPage
      }

      public mutating func next() async throws -> User? {
        while buffer.isEmpty {
          if exhausted { return nil }
          let page = try await admin.listUsers(page: nextPage, perPage: perPage)
          buffer = page.users[...]
          nextPage = page.nextPage
          exhausted = page.nextPage == nil
        }
        return buffer.removeFirst()
      }
    }

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(admin: admin, perPage: perPage)
    }
  }
}
