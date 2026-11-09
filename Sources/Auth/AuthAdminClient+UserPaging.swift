//
//  AuthAdminClient+UserPaging.swift
//  Auth
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation

extension AuthAdminClient {
  /// Every user in the project, as an `AsyncSequence` that walks the pages for you.
  ///
  /// ``listUsers(page:pageSize:)`` hands back one page and a ``UserPage/nextPage`` number to
  /// follow. This wraps that loop:
  ///
  /// ```swift
  /// for try await user in admin.users() {
  ///   print(user.email ?? user.id.uuidString)
  /// }
  ///
  /// // Page by page, with the totals
  /// for try await page in admin.users(pageSize: 50).pages {
  ///   print(page.users.count, "of", page.total)
  /// }
  /// ```
  ///
  /// A page is fetched only when the previous one runs out, so a caller that stops early —
  /// `break`, `prefix(_:)`, `first(where:)` — never pays for the pages it did not read.
  ///
  /// The cursor of `page(after:)` is the number of the page to fetch, so pass a page's
  /// ``UserPage/nextPage`` to get the page after it.
  ///
  /// - Parameter pageSize: Users per request. `nil` leaves the page size to the server.
  /// - Returns: A sequence of every user, in the order the server returns them. Iterating it, or
  ///   calling its `page(after:)`, throws ``AuthError`` if a request fails.
  public func users(pageSize: Int? = nil) -> PageSequence<User, UserPage, Int> {
    PageSequence(
      fetch: { [self] page in try await listUsers(page: page, pageSize: pageSize) },
      nextCursor: \.nextPage,
      elements: \.users
    )
  }
}
