# Listing Objects

Walk the objects under a prefix with a cursor, or read one folder at a time.

## Overview

A bucket has two listing methods.

| | ``StorageBucket/objects(prefix:options:)`` | ``StorageBucket/list(path:options:)`` |
| --- | --- | --- |
| Returns | an ``ObjectListing``, fetched as you iterate | one array, in one request |
| Paging | a cursor, carried for you | `limit` and `offset` |
| Depth | one level with folders, or every key | one level |
| Names | full keys, `"2026/beach.png"` | relative to the path, `"beach.png"` |
| Folders | ``ObjectListing/Page/folders`` | rows with ``StorageObject/isFolder`` |
| Options | ``ObjectListingOptions`` | ``ListOptions`` |

Prefer `objects`. Use `list` when you need its `search` filter or the
``ObjectSortColumn/lastAccessedAt`` sort, or on a project created before the cursor listing
existed. Such a project answers `objects` with ``StorageError/Code/featureNotEnabled``.

### Every object

Iterate the listing for every object it selects. Each page is one request, sent when the loop
needs it. Set ``ObjectListingOptions/delimited`` to `false` to include every depth.

```swift
var total: Int64 = 0
for try await object in supabase.storage.from("photos").objects(
  prefix: "2026/", options: ObjectListingOptions(delimited: false))
{
  total += object.metadata?.size ?? 0
}
```

Nothing is sent until you iterate. A failed request ends the loop with the error.

### Folders and pages

Storage has no real folders. A folder is the part of a key up to a `/`. With the default
`delimited: true`, a page lists one level: the objects directly under the prefix, and each
deeper key collapsed into a folder. Iterate ``ObjectListing/pages`` to see them, as a file
browser does.

```swift
var folders: [String] = []
var files: [StorageObject] = []
for try await page in supabase.storage.from("photos").objects(prefix: "2026/").pages {
  folders += page.folders  // ["2026/beach/", "2026/city/"]
  files += page.objects
}
```

A prefix is not a folder: `"2026"` also matches `"2026-old/a.png"`. End it with `/` to stay in
one folder. An empty prefix lists the whole bucket.

### Cursors

To fetch one page at a time, for example as a list scrolls, call ``ObjectListing/page(after:)``
and keep the page's ``ObjectListing/Page/nextCursor``.

```swift
let listing = supabase.storage.from("photos").objects(
  prefix: "2026/", options: ObjectListingOptions(pageSize: 50, sortBy: .updatedAt, order: .descending))

let first = try await listing.page()
if let cursor = first.nextCursor {
  let second = try await listing.page(after: cursor)
}
```

A cursor carries the sort and filters of its listing. Pass it only to the listing it came from.
``ObjectListing/Page/hasNext`` is `false` on the last page.

### Listing options

``ObjectListingOptions`` sets the page size (Storage caps it at 1000, folders included), the
depth, the sort and the filters. ``ObjectListingOptions/exactMatch`` treats the prefix as one
object key. ``ObjectListingOptions/versions`` and ``ObjectListingOptions/deleteMarkers`` take a
``VersionFilter`` for buckets with versioning.

### One folder with list

``StorageBucket/list(path:options:)`` returns one level under `path`, 100 entries by default.
Page with ``ListOptions/limit`` and ``ListOptions/offset``.

```swift
let files = try await supabase.storage.from("avatars").list(
  path: "users",
  options: ListOptions(limit: 50, offset: 50, sortBy: .createdAt, order: .descending, search: "avatar")
)
for file in files where !file.isFolder {
  print(file.name)
}
```

A folder arrives as a row with no ``StorageObject/id`` and no metadata.
