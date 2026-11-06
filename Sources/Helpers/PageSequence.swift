//
//  PageSequence.swift
//  Helpers
//
//  Created by Guilherme Souza on 06/11/26.
//

/// A paged listing, fetched one page per request as you iterate.
///
/// Iterate the sequence for every element of every page. Iterate ``pages`` to see each page
/// whole, with its cursor and any other fields it carries. Call ``page(after:)`` to fetch one
/// page from a cursor you kept.
///
/// ```swift
/// for try await user in admin.users() {
///   print(user.email ?? user.id.uuidString)
/// }
///
/// for try await page in storage.from("photos").objects(prefix: "2026/").pages {
///   print(page.folders, page.objects.count)
/// }
/// ```
///
/// Nothing is sent until you iterate. A page is fetched only when the previous one runs out, so a
/// caller that stops early — `break`, `prefix(_:)`, `first(where:)` — never pays for the pages it
/// did not read. Iteration ends after the page that has no next cursor, and stops at the first
/// error, which it throws. Each new iteration starts again from the first page.
///
/// ## Topics
///
/// ### Iterating
///
/// - ``pages``
/// - ``page(after:)``
/// - ``Pages``
public struct PageSequence<Element: Sendable, Page: Sendable, Cursor: Sendable>: AsyncSequence,
  Sendable
{
  /// The pages of this listing, fetched one at a time as you iterate.
  public let pages: Pages
  let elements: @Sendable (Page) -> [Element]

  /// Creates a sequence from the closures that fetch a page and read it.
  ///
  /// - Parameters:
  ///   - fetch: Fetches the page for a cursor, or the first page for `nil`.
  ///   - nextCursor: The cursor of the page after this one, or `nil` on the last page.
  ///   - elements: The elements on a page.
  package init(
    fetch: @escaping @Sendable (_ cursor: Cursor?) async throws -> Page,
    nextCursor: @escaping @Sendable (Page) -> Cursor?,
    elements: @escaping @Sendable (Page) -> [Element]
  ) {
    self.pages = Pages(fetch: fetch, nextCursor: nextCursor)
    self.elements = elements
  }

  /// Fetches one page.
  ///
  /// A cursor carries the settings of the listing it came from, so pass a cursor only to that
  /// listing.
  ///
  /// - Parameter cursor: The next cursor of the previous page, or `nil` for the first page.
  /// - Returns: The page.
  /// - Throws: The error of the request, as documented by the method that returned this sequence.
  public func page(after cursor: Cursor? = nil) async throws -> Page {
    try await pages.fetch(cursor)
  }

  /// Returns an iterator over the elements of every page, in order.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(pages: pages.makeAsyncIterator(), elements: elements)
  }

  /// Returns the elements of each page in order, fetching the next page when one runs out.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var pages: Pages.AsyncIterator
    let elements: @Sendable (Page) -> [Element]
    var buffer: IndexingIterator<[Element]> = [].makeIterator()

    /// Returns the next element, or `nil` after the last page.
    public mutating func next() async throws -> Element? {
      while true {
        if let element = buffer.next() { return element }
        guard let page = try await pages.next() else { return nil }
        buffer = elements(page).makeIterator()
      }
    }
  }

  /// The pages of a ``PageSequence``, fetched one at a time as you iterate.
  ///
  /// Each iteration step sends one request. Iteration ends after the page that has no next
  /// cursor, and stops at the first error, which it throws.
  public struct Pages: AsyncSequence, Sendable {
    let fetch: @Sendable (_ cursor: Cursor?) async throws -> Page
    let nextCursor: @Sendable (Page) -> Cursor?

    /// Returns an iterator that fetches one page per call to ``AsyncIterator/next()``.
    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(pages: self)
    }

    /// Fetches the next page on each call to ``next()``.
    public struct AsyncIterator: AsyncIteratorProtocol {
      let pages: Pages
      var cursor: Cursor?
      var isFinished = false

      /// Fetches the page after the last one returned, or returns `nil` when there is none.
      public mutating func next() async throws -> Page? {
        guard !isFinished else { return nil }
        isFinished = true
        let page = try await pages.fetch(cursor)
        cursor = pages.nextCursor(page)
        isFinished = cursor == nil
        return page
      }
    }
  }
}
