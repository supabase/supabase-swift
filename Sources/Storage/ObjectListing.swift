//
//  ObjectListing.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation

/// The pages of a cursor-paged listing, fetched one at a time as you iterate.
///
/// Each iteration step sends one request. Iteration ends after the page that has no next cursor,
/// and stops at the first error, which it throws.
///
/// ```swift
/// for try await page in storage.from("photos").objects(prefix: "2026/").pages {
///   print(page.folders, page.objects.count)
/// }
/// ```
public struct PageSequence<Page: Sendable>: AsyncSequence, Sendable {
  public typealias Element = Page

  let fetch: @Sendable (_ cursor: String?) async throws -> Page
  let nextCursor: @Sendable (Page) -> String?

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(sequence: self)
  }

  /// Fetches the next page on each call to ``next()``.
  public struct AsyncIterator: AsyncIteratorProtocol {
    let sequence: PageSequence
    var cursor: String?
    var isFinished = false

    init(sequence: PageSequence) {
      self.sequence = sequence
    }

    /// Fetches the page after the last one returned, or returns `nil` when there is none.
    public mutating func next() async throws -> Page? {
      guard !isFinished else { return nil }
      // A failed fetch ends the sequence: the iterator returns `nil` after throwing.
      isFinished = true
      let page = try await sequence.fetch(cursor)
      cursor = sequence.nextCursor(page)
      isFinished = cursor == nil
      return page
    }
  }
}

/// The objects under a prefix, listed through Storage's cursor-paged listing.
///
/// Iterate the listing for every object at every depth the options select, fetching pages as
/// needed. Iterate ``pages`` to see folders and page boundaries, as a file browser does. Call
/// ``page(after:)`` to fetch one page at a time from a cursor you kept.
///
/// ```swift
/// // Every object under "2026/", across all pages
/// var total: Int64 = 0
/// for try await object in storage.from("photos").objects(
///   prefix: "2026/", options: ObjectListingOptions(delimited: false))
/// {
///   total += object.metadata?.size ?? 0
/// }
///
/// // One level, with folders
/// for try await page in storage.from("photos").objects(prefix: "2026/").pages {
///   folders += page.folders
///   files += page.objects
/// }
/// ```
///
/// Object names are full keys, not names relative to the prefix as in
/// ``StorageBucket/list(path:options:)``.
///
/// Storage projects created before this listing existed answer with ``StorageError`` code
/// ``StorageError/Code/featureNotEnabled``; use ``StorageBucket/list(path:options:)`` there.
///
/// ## Topics
///
/// ### Iterating
///
/// - ``pages``
/// - ``page(after:)``
/// - ``Page``
public struct ObjectListing: AsyncSequence, Sendable {
  public typealias Element = StorageObject

  /// The pages of this listing.
  public typealias Pages = PageSequence<Page>

  let fetch: @Sendable (_ cursor: String?) async throws -> Page

  /// The pages of this listing, fetched one at a time as you iterate.
  public var pages: Pages {
    PageSequence(fetch: fetch, nextCursor: \.nextCursor)
  }

  /// Fetches one page.
  ///
  /// The cursor carries the sort and the filters of the first page, so pass a cursor only to the
  /// listing it came from.
  ///
  /// - Parameter cursor: The ``Page/nextCursor`` of the previous page, or `nil` for the first.
  /// - Returns: The page.
  /// - Throws: ``StorageError`` if the request fails or the caller is not authorized.
  public func page(after cursor: String? = nil) async throws -> Page {
    try await fetch(cursor)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(pages: pages.makeAsyncIterator())
  }

  /// Returns the objects of each page in order, fetching the next page when one runs out.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var pages: Pages.AsyncIterator
    var objects: IndexingIterator<[StorageObject]> = [].makeIterator()

    /// Returns the next object, or `nil` after the last page.
    public mutating func next() async throws -> StorageObject? {
      while true {
        if let object = objects.next() { return object }
        guard let page = try await pages.next() else { return nil }
        objects = page.objects.makeIterator()
      }
    }
  }

  /// One page of an ``ObjectListing``.
  public struct Page: Sendable {
    /// The objects on this page, with full keys as names.
    public let objects: [StorageObject]

    /// The folders on this page, as full prefixes ending in `/`. Empty unless the listing is
    /// ``ObjectListingOptions/delimited``.
    public let folders: [String]

    /// The cursor for the next page, or `nil` on the last page.
    public let nextCursor: String?

    /// Whether another page follows this one.
    public var hasNext: Bool { nextCursor != nil }

    /// Creates a ``Page``.
    public init(objects: [StorageObject], folders: [String] = [], nextCursor: String? = nil) {
      self.objects = objects
      self.folders = folders
      self.nextCursor = nextCursor
    }
  }
}

/// Options for ``StorageBucket/objects(prefix:options:)``.
///
/// ## Topics
///
/// ### Creating listing options
///
/// - ``init(pageSize:delimited:sortBy:order:exactMatch:versions:deleteMarkers:)``
///
/// ### Paging and shape
///
/// - ``pageSize``
/// - ``delimited``
/// - ``sortBy``
/// - ``order``
///
/// ### Filtering
///
/// - ``exactMatch``
/// - ``versions``
/// - ``deleteMarkers``
public struct ObjectListingOptions: Sendable {
  /// Entries per page. Storage defaults to and caps at 1000. Folders count toward it.
  public var pageSize: Int?

  /// Whether to list one level, collapsing deeper keys into ``ObjectListing/Page/folders``
  /// (`true`), or every key at every depth (`false`). Defaults to `true`.
  public var delimited: Bool

  /// The column to sort by: ``ObjectSortColumn/name``, ``ObjectSortColumn/updatedAt`` or
  /// ``ObjectSortColumn/createdAt``. Defaults to the name.
  public var sortBy: ObjectSortColumn?

  /// The sort direction. Defaults to ascending.
  public var order: SortOrder?

  /// Whether the prefix names one object rather than the start of keys.
  public var exactMatch: Bool?

  /// Whether noncurrent versions of versioned objects are left out, included, or the only
  /// entries returned.
  public var versions: VersionFilter?

  /// Whether delete markers are left out, included, or the only entries returned.
  public var deleteMarkers: VersionFilter?

  /// Creates an ``ObjectListingOptions`` value.
  ///
  /// - Parameters:
  ///   - pageSize: Entries per page.
  ///   - delimited: Whether to list one level with folders, or every key at every depth.
  ///   - sortBy: The column to sort by.
  ///   - order: The sort direction.
  ///   - exactMatch: Whether the prefix names one object.
  ///   - versions: The filter for noncurrent versions.
  ///   - deleteMarkers: The filter for delete markers.
  public init(
    pageSize: Int? = nil,
    delimited: Bool = true,
    sortBy: ObjectSortColumn? = nil,
    order: SortOrder? = nil,
    exactMatch: Bool? = nil,
    versions: VersionFilter? = nil,
    deleteMarkers: VersionFilter? = nil
  ) {
    self.pageSize = pageSize
    self.delimited = delimited
    self.sortBy = sortBy
    self.order = order
    self.exactMatch = exactMatch
    self.versions = versions
    self.deleteMarkers = deleteMarkers
  }
}

extension StorageBucket {
  /// Lists the objects under a prefix, one page per request, as you iterate.
  ///
  /// Nothing is sent until you iterate the returned ``ObjectListing``, its
  /// ``ObjectListing/pages``, or call ``ObjectListing/page(after:)``.
  ///
  /// ```swift
  /// for try await object in storage.from("photos").objects(prefix: "2026/") {
  ///   print(object.name)  // "2026/beach.png"
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - prefix: The start of the keys to list, e.g. `"2026/"`. A prefix is not a folder:
  ///     `"2026"` also matches `"2026-old/a.png"`. Empty lists the whole bucket.
  ///   - options: Page size, folder style, sort and filters.
  /// - Returns: The listing. Iterating it throws ``StorageError`` if a request fails, the caller
  ///   is not authorized, or `prefix` has a `.` or `..` segment.
  public func objects(
    prefix: String = "",
    options: ObjectListingOptions = ObjectListingOptions()
  ) -> ObjectListing {
    ObjectListing { [api, id] cursor in
      let response = try await api.execute(
        api.requests.objects(
          bucket: id, prefix: ListPrefix(prefix), options: options, cursor: cursor)
      )
      .decoded(as: ListV2Response.self)
      return ObjectListing.Page(
        objects: response.objects,
        folders: response.folders?.map(\.name) ?? [],
        nextCursor: response.hasNext ? response.nextCursor : nil)
    }
  }
}

/// The body of `POST object/list-v2/{bucket}`.
struct ListV2Response: Decodable {
  struct Folder: Decodable {
    let name: String
  }

  let hasNext: Bool
  let nextCursor: String?
  let folders: [Folder]?
  let objects: [StorageObject]
}

/// A list-v2 prefix: normalized like an ``ObjectKey``, but a trailing `/` is kept, because
/// `photos/` and `photos` select different keys.
struct ListPrefix {
  let path: String

  init(_ prefix: String) throws {
    let key = try ObjectKey(prefix: prefix)
    path = key.path.isEmpty || !prefix.hasSuffix("/") ? key.path : key.path + "/"
  }
}

/// A token-paged listing: iterate it for the elements of every page, iterate ``pages`` for the
/// pages, or call ``page(after:)`` for one page.
///
/// - Warning: Experimental. See ``StorageVectorsClient``.
@_spi(Experimental)
public struct PagedListing<Page: Sendable, Element>: AsyncSequence, Sendable {
  let fetch: @Sendable (_ token: String?) async throws -> Page
  let nextToken: @Sendable (Page) -> String?
  let elements: @Sendable (Page) -> [Element]

  /// The pages of this listing, fetched one at a time as you iterate.
  public var pages: PageSequence<Page> {
    PageSequence(fetch: fetch, nextCursor: nextToken)
  }

  /// Fetches one page.
  ///
  /// - Parameter token: The `nextToken` of the previous page, or `nil` for the first.
  /// - Returns: The page.
  /// - Throws: ``StorageError`` when the API rejects the request.
  public func page(after token: String? = nil) async throws -> Page {
    try await fetch(token)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(pages: pages.makeAsyncIterator(), elements: elements)
  }

  /// Returns the elements of each page in order, fetching the next page when one runs out.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var pages: PageSequence<Page>.AsyncIterator
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
}
