# ``StorageIceberg``

Manage the Apache Iceberg namespaces and tables in a Supabase Storage analytics bucket.

## Overview

An analytics bucket holds Apache Iceberg tables. Supabase Storage serves an Iceberg REST catalog
for each bucket. This library is a client for that catalog: it creates, lists, loads, updates,
and deletes namespaces and tables. It does not read or write table data. To read or write the
data, give the table metadata to an Iceberg engine.

> Warning: Analytics buckets are a public alpha feature of Supabase Storage. This library is
> experimental. It can change in a breaking way, or be unavailable on your project, until the
> feature reaches general availability.

Every symbol of this library is `@_spi(Experimental)`, so this page does not link to them. The
documentation of `IcebergCatalog` groups every type of the library.

### Add the library

`StorageIceberg` is an opt-in library. The `Supabase` library does not include it. Add the
`StorageIceberg` product to your target, then import it with `@_spi(Experimental)`. Import
`Supabase` (or `Storage`) the same way, because `StorageClient.analytics` is experimental too:

```swift
@_spi(Experimental) import StorageIceberg
@_spi(Experimental) import Supabase
```

### Create a namespace and a table

Get an `IcebergCatalog` for a bucket from `catalog(bucket:)` on `supabase.storage.analytics`.
Every call needs the `secret` key.

```swift
let catalog = supabase.storage.analytics.catalog(bucket: "events")

try await catalog.createNamespace("sales", properties: ["owner": "data-team"])

let schema = IcebergSchema(fields: [
  IcebergField(id: 1, name: "id", type: .long, isRequired: true),
  IcebergField(id: 2, name: "placed_at", type: .timestamptz, isRequired: true),
  IcebergField(id: 3, name: "total", type: .decimal(precision: 10, scale: 2), isRequired: false),
])
let partitionSpec = IcebergPartitionSpec(specID: 0, fields: [
  IcebergPartitionField(sourceID: 2, name: "placed_at_day", transform: .day)
])

let table = try await catalog.createTable(
  IcebergTableCreation(name: "orders", schema: schema, partitionSpec: partitionSpec),
  in: "sales"
)
print(table.metadata.location ?? "")
```

### Commit changes to a table

`updateTable(_:in:requirements:updates:)` sends one atomic commit. The catalog checks every
`IcebergTableRequirement`, then applies every `IcebergTableUpdate` in order. The factories that
take a model, such as `addSchema(_:lastColumnID:)`, throw when the model cannot be encoded:

```swift
let loaded = try await catalog.table("orders", in: "sales")
let fields = loaded.metadata.currentSchema?.fields ?? []
let schema = IcebergSchema(
  fields: fields + [IcebergField(id: 4, name: "note", type: .string, isRequired: false)]
)

try await catalog.updateTable(
  "orders",
  in: "sales",
  requirements: [.assertCurrentSchemaID(loaded.metadata.currentSchemaID ?? 0)],
  updates: [try .addSchema(schema), .setCurrentSchema(id: -1)]
)
```

### Handle errors

Every call throws `StorageError` when the catalog rejects the request. The catalog's own error
type, such as `NoSuchTableException`, is in the error's `code`. A cancelled task throws
`CancellationError`.
