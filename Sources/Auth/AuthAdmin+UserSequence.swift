//
//  AuthAdmin+UserSequence.swift
//  Auth
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation

extension AuthAdmin {
  /// Every user in the project, as an `AsyncSequence` that walks the pages for you.
  ///
  /// ``listUsers(params:)`` hands back one page and a ``ListUsersPaginatedResponse/nextPage``
  /// cursor to follow. This wraps that loop:
  ///
  /// ```swift
  /// for try await user in client.auth.admin.users() {
  ///   print(user.email ?? user.id.uuidString)
  /// }
  /// ```
  ///
  /// A page is fetched only when the previous one runs out, so a caller that stops early —
  /// `break`, `prefix(_:)`, `first(where:)` — never pays for the pages it did not read.
  ///
  /// - Parameter perPage: Users per request. `nil` leaves the page size to the server.
  /// - Returns: A sequence of every user, in the order the server returns them.
  ///
  /// > Warning: This requires the secret key. Never expose that key in a browser or mobile app —
  /// > call this from a secure server-side environment only.
  public func users(perPage: Int? = nil) -> UserSequence {
    UserSequence(admin: self, perPage: perPage)
  }

  /// An `AsyncSequence` over every user in the project, fetched one page at a time.
  ///
  /// Create one with ``AuthAdmin/users(perPage:)``.
  public struct UserSequence: AsyncSequence, Sendable {
    public typealias Element = User

    let admin: AuthAdmin
    let perPage: Int?

    public struct AsyncIterator: AsyncIteratorProtocol {
      let admin: AuthAdmin
      let perPage: Int?

      /// Users from the most recent page that the caller has not consumed yet.
      private var buffer: ArraySlice<User> = []
      /// The page to request next, or `nil` on the first call (the server picks page one).
      private var nextPage: Int?
      /// Set once the server stops advertising a `next` link.
      private var exhausted = false

      init(admin: AuthAdmin, perPage: Int?) {
        self.admin = admin
        self.perPage = perPage
      }

      public mutating func next() async throws -> User? {
        // A page can come back empty while a later one still has users, so keep going until
        // the buffer fills or the server says there is nothing left.
        while buffer.isEmpty {
          if exhausted { return nil }
          let response = try await admin.listUsers(
            params: PageParams(page: nextPage, perPage: perPage)
          )
          buffer = response.users[...]
          nextPage = response.nextPage
          exhausted = response.nextPage == nil
        }
        return buffer.removeFirst()
      }
    }

    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(admin: admin, perPage: perPage)
    }
  }
}
