# Listing Objects

Walk the objects under a prefix with a cursor, or read one folder at a time.

## Overview

``StorageBucket/objects(prefix:options:)`` lists a bucket. It returns an ``ObjectListing``,
which fetches one page per request as you iterate and follows Storage's cursor for you. Names
are full keys, such as `"2026/beach.png"`, and folders arrive apart from objects, as full
prefixes ending in `/`.

A Storage server that predates this listing answers with
``StorageError/Code/featureNotEnabled``.

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
object key. ``ObjectListingOptions/sortBy`` takes ``ObjectSortColumn/name``,
``ObjectSortColumn/updatedAt`` or ``ObjectSortColumn/createdAt``.
``ObjectListingOptions/versions`` and ``ObjectListingOptions/deleteMarkers`` take a
``VersionFilter`` for buckets with versioning.

The listing has no name search. To narrow a listing, list a longer prefix, or filter the names
as you iterate.
