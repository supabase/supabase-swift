//
//  ObjectListing.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation

/// One page of ``StorageBucket/objects(prefix:options:)``.
///
/// Iterate the listing's `pages` to get each page, or call
/// `page(after:)` with a ``nextCursor`` you kept.
public struct ObjectPage: Sendable {
  /// The objects on this page, with full keys as names.
  public let objects: [StorageObject]

  /// The folders on this page, as full prefixes ending in `/`. Empty unless the listing is
  /// ``ObjectListingOptions/delimited``.
  public let folders: [String]

  /// The cursor for the next page, or `nil` on the last page.
  public let nextCursor: String?

  /// Whether another page follows this one.
  public var hasNext: Bool { nextCursor != nil }

  /// Creates an ``ObjectPage``.
  public init(objects: [StorageObject], folders: [String] = [], nextCursor: String? = nil) {
    self.objects = objects
    self.folders = folders
    self.nextCursor = nextCursor
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

  /// Whether to list one level, collapsing deeper keys into ``ObjectPage/folders``
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
  /// Iterate the listing for every object at every depth the options select. Iterate its
  /// `pages` to see folders and page boundaries, as a file browser does. Call
  /// `page(after:)` to fetch one page from a cursor you kept. Nothing is sent
  /// until you do one of these.
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
  /// Object names are full keys, such as `"2026/beach.png"`, not names relative to the prefix as
  /// in ``StorageBucket/list(path:options:)``. The cursor carries the sort and the filters of the
  /// first page, so pass a cursor only to the listing it came from.
  ///
  /// Storage projects created before this listing existed answer with ``StorageError`` code
  /// ``StorageError/Code/featureNotEnabled``; use ``StorageBucket/list(path:options:)`` there.
  ///
  /// - Parameters:
  ///   - prefix: The start of the keys to list, e.g. `"2026/"`. A prefix is not a folder:
  ///     `"2026"` also matches `"2026-old/a.png"`. Empty lists the whole bucket.
  ///   - options: Page size, folder style, sort and filters.
  /// - Returns: The listing. Iterating it, or calling its `page(after:)`, throws ``StorageError`` if
  ///   a request fails, the caller is not authorized, or `prefix` has a `.` or `..` segment.
  public func objects(
    prefix: String = "",
    options: ObjectListingOptions = ObjectListingOptions()
  ) -> PageSequence<StorageObject, ObjectPage, String> {
    PageSequence(
      fetch: { [api, id] cursor in
        let response = try await api.execute(
          api.requests.objects(
            bucket: id, prefix: ListPrefix(prefix), options: options, cursor: cursor)
        )
        .decoded(as: ListV2Response.self)
        return ObjectPage(
          objects: response.objects,
          folders: response.folders?.map(\.name) ?? [],
          nextCursor: response.hasNext ? response.nextCursor : nil)
      },
      nextCursor: \.nextCursor,
      elements: \.objects
    )
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
