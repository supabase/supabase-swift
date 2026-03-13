# Migration Guide: v2.x → v3.0

This guide helps you migrate from supabase-swift v2.x to v3.0. The v3.0 release removes all deprecated code accumulated over the v2.x lifecycle (~4,676 lines), providing a cleaner, more maintainable SDK.

## Table of Contents

- [Breaking Changes Overview](#breaking-changes-overview)
- [Realtime](#realtime)
- [Auth](#auth)
- [PostgREST](#postgrest)
- [Storage](#storage)
- [Supabase Client](#supabase-client)

---

## Breaking Changes Overview

### Summary

- **Realtime Protocol 1.0** completely removed (use Protocol 2.0)
- **Deprecated constructors** removed (all modules now require `logger` parameter)
- **Deprecated methods** removed across Auth, PostgREST, Storage
- **Deprecated type aliases** removed (GoTrue* → Auth*, etc.)
- **Deprecated properties** removed (`.database`, `.realtime`, etc.)

### Lines Removed

- **3,726 lines**: Realtime Protocol 1.0 implementation
- **950 lines**: Deprecated methods, constructors, properties
- **~4,676 lines total** deprecated code removed

---

## Realtime

### Protocol 1.0 Removed

**What changed**: The entire Realtime Protocol 1.0 implementation has been removed. Only Protocol 2.0 (RealtimeV2) is supported.

**Migration**:

```swift
// ❌ Old (v2.x) - Protocol 1.0
let client = supabase.realtime // Deprecated, removed in v3
let channel = client.channel("public:messages")

// ✅ New (v3.0) - Protocol 2.0
let client = supabase.realtimeV2
let channel = client.channel("public:messages")
```

For detailed Realtime v1 → v2 migration, see the [Realtime V2 Migration Guide](https://github.com/supabase-community/supabase-swift/blob/main/docs/migrations/RealtimeV2%20Migration%20Guide.md).

### Deprecated Methods Removed

#### 1. `RealtimeChannelV2.subscribe()`

**Removed**: Deprecated async method that swallowed errors.

**Migration**:

```swift
// ❌ Old (v2.x)
await channel.subscribe()

// ✅ New (v3.0)
try await channel.subscribeWithError()
```

#### 2. `RealtimeChannelV2.broadcast(event:)` (receiving)

**Removed**: Deprecated receiving method that returned `AsyncStream<JSONObject>`.

**Migration**:

```swift
// ❌ Old (v2.x) - receiving broadcasts
for await message in channel.broadcast(event: "test-event") {
  print(message)
}

// ✅ New (v3.0)
for await message in channel.broadcastStream(event: "test-event") {
  print(message)
}
```

**Note**: The **sending** `broadcast(event:message:)` method is NOT deprecated and continues to work.

### Type Aliases Removed

The following deprecated type aliases have been removed:

| Removed Alias | Use Instead |
|---------------|-------------|
| `Message` | `RealtimeMessage` |
| `Configuration` | `RealtimeClientOptions` |
| `Status` | `RealtimeClientStatus` |
| `Subscription` | `ObservationToken` or `RealtimeSubscription` |
| `RealtimeChannelV2.Status` | `RealtimeChannelStatus` |

### Properties Removed

- **`RealtimeClientV2.subscriptions`** → Use `.channels` instead

```swift
// ❌ Old (v2.x)
let allChannels = client.subscriptions.values

// ✅ New (v3.0)
let allChannels = client.channels.values
```

---

## Auth

### Deprecated Constructors Removed

**What changed**: Old constructor signatures without `logger` parameter have been removed.

**Migration**:

```swift
// ❌ Old (v2.x)
let authClient = AuthClient(
  url: url,
  headers: headers
)

// ✅ New (v3.0) - logger parameter required
let authClient = AuthClient(
  url: url,
  headers: headers,
  logger: myLogger // or nil
)

// For SupabaseClient, this is handled automatically
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: SupabaseClientOptions(
    auth: .init(
      logger: myLogger // Optional
    )
  )
)
```

### Deprecated Methods Removed

#### `AuthAdmin.deleteUser(id: String)`

**Removed**: String-based ID method.

**Migration**:

```swift
// ❌ Old (v2.x)
try await client.auth.admin.deleteUser(id: "user-id-string")

// ✅ New (v3.0) - UUID required
try await client.auth.admin.deleteUser(id: UUID(uuidString: "user-id-string")!)
```

### Deprecated Error Cases Removed

The following error cases have been removed:

| Removed Error | Reason / Migration |
|---------------|-------------------|
| `.missingExpClaim` | Never thrown, safe to remove |
| `.malformedJWT` | Never thrown, safe to remove |
| `.sessionNotFound` | Use `.sessionMissing` instead |
| `.pkce(_:)` | Use `.pkceGrantCodeExchange(message:underlyingError:underlyingResponse:)` instead |
| `.PKCEFailureReason` | Use `.pkceGrantCodeExchange` instead |
| `.invalidImplicitGrantFlowURL` | Use `.implicitGrantRedirect(message:)` instead |
| `.missingURL` | Never thrown, safe to remove |
| `.invalidRedirectScheme` | Now triggers assertion instead |

**Migration example**:

```swift
// ❌ Old (v2.x)
if case .sessionNotFound = error {
  // Handle missing session
}

// ✅ New (v3.0)
if case .sessionMissing = error {
  // Handle missing session
}
```

### Deprecated Properties Removed

#### `User.emailChangeToken`

**Removed**: Old field no longer used by the API.

**Migration**: Simply remove any code that reads or writes this property.

```swift
// ❌ Old (v2.x)
let token = user.emailChangeToken

let attributes = UserAttributes(
  email: "new@email.com",
  emailChangeToken: "token" // Removed
)

// ✅ New (v3.0)
let attributes = UserAttributes(
  email: "new@email.com"
  // emailChangeToken parameter removed
)
```

### Type Aliases Removed

| Removed Alias | Use Instead |
|---------------|-------------|
| `GoTrueClient` | `AuthClient` |
| `GoTrueMFA` | `AuthMFA` |
| `GoTrueLocalStorage` | `AuthLocalStorage` |
| `GoTrueMetaSecurity` | `AuthMetaSecurity` |
| `GoTrueError` | `AuthError` |
| `MFAEnrollParams` | `MFATotpEnrollParams` or `MFAPhoneEnrollParams` |

**Migration**:

```swift
// ❌ Old (v2.x)
let client: GoTrueClient = ...
let params = MFAEnrollParams(issuer: "app", friendlyName: "device")

// ✅ New (v3.0)
let client: AuthClient = ...
let params = MFATotpEnrollParams(issuer: "app", friendlyName: "device")
```

---

## PostgREST

### Deprecated Constructors Removed

**What changed**: Old constructor signature without `logger` parameter removed.

**Migration**:

```swift
// ❌ Old (v2.x)
let postgrest = PostgrestClient(
  url: url,
  headers: headers
)

// ✅ New (v3.0)
let postgrest = PostgrestClient(
  url: url,
  headers: headers,
  logger: myLogger // or nil
)

// For SupabaseClient, this is handled automatically
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: SupabaseClientOptions(
    db: .init(
      logger: myLogger // Optional
    )
  )
)
```

### Deprecated Filter Methods Removed

The following filter methods with old signatures have been removed:

| Removed Method | Use Instead |
|----------------|-------------|
| `.like(_ column:, value:)` | `.like(_:pattern:)` |
| `.ilike(_ column:, value:)` | `.ilike(_:pattern:)` |
| `.in(_ column:, value:)` | `.in(_:values:)` |
| `.plfts()` | `.textSearch(_:query:config:type:)` with `.plain` |
| `.phfts()` | `.textSearch(_:query:config:type:)` with `.phrase` |
| `.wfts()` | `.textSearch(_:query:config:type:)` with `.websearch` |

**Migration examples**:

```swift
// ❌ Old (v2.x)
try await client
  .from("users")
  .select()
  .like("name", value: "John%")
  .execute()

// ✅ New (v3.0)
try await client
  .from("users")
  .select()
  .like("name", pattern: "John%")
  .execute()
```

```swift
// ❌ Old (v2.x)
try await client
  .from("users")
  .select()
  .in("status", value: ["active", "pending"])
  .execute()

// ✅ New (v3.0)
try await client
  .from("users")
  .select()
  .in("status", values: ["active", "pending"])
  .execute()
```

```swift
// ❌ Old (v2.x)
try await client
  .from("docs")
  .select()
  .plfts("title", query: "search terms")
  .execute()

// ✅ New (v3.0)
try await client
  .from("docs")
  .select()
  .textSearch("title", query: "search terms", type: .plain)
  .execute()
```

### Deprecated Properties Removed

#### `PostgrestFilterValue.queryValue`

**Removed**: Use `.rawValue` instead.

**Migration**:

```swift
// ❌ Old (v2.x)
let value: PostgrestFilterValue = "test"
let query = value.queryValue

// ✅ New (v3.0)
let value: PostgrestFilterValue = "test"
let query = value.rawValue
```

### Type Aliases Removed

| Removed Alias | Use Instead |
|---------------|-------------|
| `URLQueryRepresentable` | `PostgrestFilterValue` |

---

## Storage

### Deprecated Constructors Removed

**What changed**: Old constructor signature without `logger` parameter removed.

**Migration**:

```swift
// ❌ Old (v2.x)
let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: url,
    headers: headers
  )
)

// ✅ New (v3.0)
let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: url,
    headers: headers,
    logger: myLogger // or nil
  )
)

// For SupabaseClient, this is handled automatically
let client = SupabaseClient(
  supabaseURL: url,
  supabaseKey: key,
  options: SupabaseClientOptions(
    global: .init(
      logger: myLogger // Optional
    )
  )
)
```

### Deprecated Upload Methods Removed

#### Methods with String Return Type

**Removed**: Upload methods that returned `String` (the path).

**Migration**:

```swift
// ❌ Old (v2.x) - returns String
let path = try await storage
  .from("avatars")
  .upload(path: "user.jpg", file: data)

// ✅ New (v3.0) - returns FileUploadResponse
let response = try await storage
  .from("avatars")
  .upload(path: "user.jpg", data: data)

print(response.path) // Access path from response
print(response.id)   // Also get file ID
```

#### Methods with Parameter Renames

Several upload methods renamed `file:` parameter to `data:`:

| Removed Method | Use Instead |
|----------------|-------------|
| `.upload(path:file:options:)` | `.upload(_:data:options:)` |
| `.update(path:file:options:)` | `.update(_:data:options:)` |
| `.uploadToSignedURL(path:token:file:)` | `.updateToSignedURL(_:token:data:options:)` |

**Migration**:

```swift
// ❌ Old (v2.x)
try await storage
  .from("bucket")
  .upload(path: "file.jpg", file: data)

// ✅ New (v3.0)
try await storage
  .from("bucket")
  .upload("file.jpg", data: data)
```

### Deprecated Types Removed

#### `File` Struct

**Removed**: Replaced by `FileUploadResponse`.

**Migration**:

```swift
// ❌ Old (v2.x)
let file: File = ...
print(file.Key)

// ✅ New (v3.0)
let response: FileUploadResponse = ...
print(response.path)
print(response.id)
print(response.fullPath)
```

#### `FormData` Class

**Removed**: Use `MultipartFormData` instead.

**Migration**: If you were using `FormData` directly (rare), migrate to `MultipartFormData`. Most users won't need to change anything as this is handled internally.

### Deprecated Encoder/Decoder Access Removed

**What changed**: Public access to `defaultStorageEncoder` and `defaultStorageDecoder` removed.

**Migration**: These were internal utilities. If you need custom encoding/decoding, provide your own encoder/decoder to the `SupabaseStorageClient` initializer.

```swift
// ❌ Old (v2.x)
JSONEncoder.defaultStorageEncoder.outputFormatting = [.sortedKeys]

// ✅ New (v3.0) - provide custom encoder if needed
let customEncoder = JSONEncoder()
customEncoder.keyEncodingStrategy = .convertToSnakeCase
customEncoder.outputFormatting = [.sortedKeys]

let storage = SupabaseStorageClient(
  configuration: StorageClientConfiguration(
    url: url,
    headers: headers,
    encoder: customEncoder // Use custom encoder
  )
)
```

---

## Supabase Client

### Deprecated Properties Removed

#### `.database` Property

**Removed**: Direct access to database client.

**Migration**: Use specific methods instead.

```swift
// ❌ Old (v2.x)
let postgrest = client.database

// ✅ New (v3.0) - use specific methods
let query = client.from("table") // For queries
let rpc = client.rpc("function")  // For RPC calls
let schema = client.schema("custom_schema") // For custom schemas
```

#### `.realtime` Property

**Removed**: Realtime Protocol 1.0 client access.

**Migration**: Use `.realtimeV2` instead.

```swift
// ❌ Old (v2.x)
let realtime = client.realtime

// ✅ New (v3.0)
let realtime = client.realtimeV2
```

---

## Helpers

### `ObservationToken.remove()` Still Available

**Note**: Despite the issue description mentioning removal of `ObservationToken.remove()`, this method is **NOT deprecated** and remains available. It's required by the `AuthStateChangeListenerRegistration` protocol.

Both `.remove()` and `.cancel()` continue to work:

```swift
// ✅ Both work in v3.0
let subscription = channel.onBroadcast(event: "test") { message in
  print(message)
}

subscription.cancel() // Option 1
subscription.remove() // Option 2
```

---

## Checklist for Migration

Use this checklist to ensure you've covered all breaking changes:

### Realtime
- [ ] Migrated from Protocol 1.0 to Protocol 2.0 (`.realtime` → `.realtimeV2`)
- [ ] Updated `.subscribe()` to `.subscribeWithError()`
- [ ] Updated receiving `.broadcast(event:)` to `.broadcastStream(event:)`
- [ ] Updated `.subscriptions` to `.channels`
- [ ] Updated type aliases (Message, Configuration, Status, etc.)

### Auth
- [ ] Added `logger` parameter to custom `AuthClient` initializers
- [ ] Updated `deleteUser(id: String)` to `deleteUser(id: UUID)`
- [ ] Updated error handling for removed error cases
- [ ] Removed `emailChangeToken` property usage
- [ ] Updated type aliases (GoTrue* → Auth*)
- [ ] Updated `MFAEnrollParams` to `MFATotpEnrollParams` or `MFAPhoneEnrollParams`

### PostgREST
- [ ] Added `logger` parameter to custom `PostgrestClient` initializers
- [ ] Updated filter methods (`.like`, `.in`, text search methods)
- [ ] Updated `.queryValue` to `.rawValue`
- [ ] Updated type aliases (URLQueryRepresentable → PostgrestFilterValue)

### Storage
- [ ] Added `logger` parameter to custom storage initializers
- [ ] Updated upload methods to use new signatures and return types
- [ ] Removed `File` type usage (use `FileUploadResponse`)
- [ ] Removed direct encoder/decoder access

### Supabase Client
- [ ] Replaced `.database` with `.from()`, `.rpc()`, or `.schema()`
- [ ] Replaced `.realtime` with `.realtimeV2`

---

## Getting Help

If you encounter issues during migration:

1. Check the [API Documentation](https://supabase.github.io/supabase-swift/documentation/)
2. Search [GitHub Issues](https://github.com/supabase/supabase-swift/issues)
3. Ask in [Discord](https://discord.supabase.com) #swift channel
4. File a [Bug Report](https://github.com/supabase/supabase-swift/issues/new)

---

## Summary

The v3.0 release removes ~4,676 lines of deprecated code, resulting in a cleaner, more maintainable SDK. While this introduces breaking changes, all removed APIs have clear migration paths, and the effort required for migration is typically straightforward find-and-replace operations.

Most importantly, this cleanup positions the SDK for future enhancements without the burden of maintaining deprecated code paths.

