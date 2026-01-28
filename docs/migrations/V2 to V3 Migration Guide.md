# Supabase Swift v2 to v3 Migration Guide

This guide covers the breaking changes when migrating from Supabase Swift v2 to v3. The v3 release removes all deprecated APIs, providing a cleaner and more consistent API surface.

## Auth Module

### Type Aliases Removed

The following type aliases have been removed. Use the new names directly:

| Old Name | New Name |
|----------|----------|
| `GoTrueClient` | `AuthClient` |
| `GoTrueMFA` | `AuthMFA` |
| `GoTrueLocalStorage` | `AuthLocalStorage` |
| `GoTrueMetaSecurity` | `AuthMetaSecurity` |
| `GoTrueError` | `AuthError` |

### JSON Encoder/Decoder

The static properties `JSONEncoder.goTrue` and `JSONDecoder.goTrue` have been removed. If you need custom encoding/decoding, configure your own encoder/decoder and pass it to `AuthClient.Configuration`.

```swift
// Before
let encoder = JSONEncoder.goTrue

// After
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
// Pass to AuthClient.Configuration
```

### Configuration and Initialization

The `AuthClient.Configuration` and `AuthClient` initializers now require a `logger` parameter:

```swift
// Before
let config = AuthClient.Configuration(
    url: authURL,
    headers: headers
)

// After
let config = AuthClient.Configuration(
    url: authURL,
    headers: headers,
    logger: nil // or provide a logger
)
```

### MFA Enrollment

`MFAEnrollParams` has been removed. Use the specific enroll params types instead:

```swift
// Before
try await client.mfa.enroll(
    params: MFAEnrollParams(issuer: "app", friendlyName: "My TOTP")
)

// After - for TOTP
try await client.mfa.enroll(
    params: MFATotpEnrollParams(issuer: "app", friendlyName: "My TOTP")
)

// After - for Phone
try await client.mfa.enroll(
    params: MFAPhoneEnrollParams(friendlyName: "My Phone", phone: "+1234567890")
)

// Or use the convenience methods
try await client.mfa.enroll(params: .totp(issuer: "app", friendlyName: "My TOTP"))
try await client.mfa.enroll(params: .phone(friendlyName: "My Phone", phone: "+1234567890"))
```

### Admin User Deletion

`AuthAdmin.deleteUser(id: String)` now requires a `UUID`:

```swift
// Before
try await client.admin.deleteUser(id: "user-id-string")

// After
try await client.admin.deleteUser(id: UUID(uuidString: "user-id-string")!)
```

### UserAttributes

The `emailChangeToken` property has been removed from `UserAttributes`.

### UserCredentials

The `UserCredentials` struct has been removed. This was an internal type that should not have been public.

### AuthError Changes

Several deprecated error cases and factory methods have been removed:

| Removed | Replacement |
|---------|-------------|
| `AuthError.sessionNotFound` | `AuthError.sessionMissing` |
| `AuthError.pkce(_:)` | `AuthError.pkceGrantCodeExchange(message:)` |
| `AuthError.invalidImplicitGrantFlowURL` | `AuthError.implicitGrantRedirect(message:)` |
| `AuthError.api(_ error: APIError)` | `AuthError.api(message:errorCode:underlyingData:underlyingResponse:)` |
| `AuthError.missingExpClaim` | Removed (never thrown) |
| `AuthError.malformedJWT` | Removed (never thrown) |
| `AuthError.missingURL` | Removed (never thrown) |
| `AuthError.invalidRedirectScheme` | Removed (never thrown) |
| `AuthError.PKCEFailureReason` | Removed |
| `AuthError.APIError` | Removed |

### Listener Registration

The `remove()` method on `AuthStateChangeListenerRegistration` has been renamed to `cancel()`:

```swift
// Before
let handle = await client.onAuthStateChange { event, session in }
handle.remove()

// After
let handle = await client.onAuthStateChange { event, session in }
handle.cancel()
```

## PostgREST Module

### Configuration and Initialization

The `PostgrestClient.Configuration` and `PostgrestClient` initializers now require a `logger` parameter.

### Filter Methods Renamed

| Old Method | New Method |
|------------|------------|
| `like(_ column:value:)` | `like(_ column:pattern:)` |
| `ilike(_ column:value:)` | `ilike(_ column:pattern:)` |
| `in(_ column:value:)` | `in(_ column:values:)` |

### Text Search Methods Replaced

The individual text search methods have been consolidated:

```swift
// Before
query.plfts(column: "content", query: "search")
query.phfts(column: "content", query: "search")
query.wfts(column: "content", query: "search")

// After
query.textSearch("content", query: "search", type: .plain)
query.textSearch("content", query: "search", type: .phrase)
query.textSearch("content", query: "search", type: .websearch)
```

### Type Alias Removed

`URLQueryRepresentable` has been renamed to `PostgrestFilterValue`.

### Property Renamed

The `queryValue` property on `PostgrestFilterValue` has been renamed to `rawValue`.

## Storage Module

### Configuration

The `StorageClientConfiguration` initializer now requires a `logger` parameter.

### Upload Methods

Upload methods that returned `String` now return typed response objects:

```swift
// Before
let path: String = try await storage.from("bucket").upload(path: "file.txt", file: data)

// After
let response: FileUploadResponse = try await storage.from("bucket").upload("file.txt", data: data)
let path = response.path
```

Similarly for `update` and `uploadToSignedURL`.

### Parameter Renamed

The `file` parameter has been renamed to `data`:

```swift
// Before
try await storage.from("bucket").upload(path: "file.txt", file: data)

// After
try await storage.from("bucket").upload("file.txt", data: data)
```

### Removed Types

- `File` struct - Use `Data` directly
- `FormData` class - Use `MultipartFormData` instead

### JSON Encoder/Decoder

`JSONEncoder.defaultStorageEncoder` and `JSONDecoder.defaultStorageDecoder` have been removed. Use `JSONEncoder.storage()` and `JSONDecoder.storage()` if you need the default configuration.

## Realtime Module

### V1 Classes Removed

The entire Realtime V1 implementation has been removed:

- `RealtimeClient` - Use `RealtimeClientV2`
- `RealtimeChannel` - Use `RealtimeChannelV2`
- `Presence` - Use `PresenceV2`

See the [RealtimeV2 Migration Guide](./RealtimeV2%20Migration%20Guide.md) for detailed migration instructions.

### Type Aliases Removed

| Old Name | New Name |
|----------|----------|
| `Message` | `RealtimeMessage` |
| `RealtimeClientV2.Configuration` | `RealtimeClientOptions` |
| `RealtimeClientV2.Status` | `RealtimeClientStatus` |
| `RealtimeChannelV2.Subscription` | `ObservationToken` |
| `RealtimeChannelV2.Status` | `RealtimeChannelStatus` |

### Properties Renamed

| Old Property | New Property |
|--------------|--------------|
| `RealtimeClientV2.subscriptions` | `RealtimeClientV2.channels` |

### Initialization Changed

```swift
// Before
let client = RealtimeClientV2(config: .init(url: url, apiKey: key))

// After
let client = RealtimeClientV2(url: url, options: RealtimeClientOptions(apiKey: key))
```

### Subscribe Method

The non-throwing `subscribe()` method has been removed. Use `subscribeWithError()` instead:

```swift
// Before
await channel.subscribe()

// After
try await channel.subscribeWithError()
```

### Auth Updates

The per-channel `updateAuth(jwt:)` method has been removed. Use the client-level method instead:

```swift
// Before
await channel.updateAuth(jwt: token)

// After
await client.setAuth(token)
```

### Postgres Change Filter

The `filter` parameter type has changed from `String?` to `RealtimePostgresFilter?`:

```swift
// Before
channel.postgresChange(InsertAction.self, filter: "id=eq.1")

// After
channel.postgresChange(InsertAction.self, filter: .eq("id", value: "1"))
```

### Broadcast Stream

The `broadcast(event:)` method has been renamed to `broadcastStream(event:)`:

```swift
// Before
for await message in channel.broadcast(event: "cursor") { }

// After
for await message in channel.broadcastStream(event: "cursor") { }
```

### Channel Management

The `addChannel(_:)` method has been removed. The client now manages channels automatically.

### EventType

The `RealtimeMessageV2.eventType` property and `RealtimeMessageV2.EventType.tokenExpired` case have been removed. Inspect the raw `event` property directly.

## SupabaseClient

### Database Property Removed

The `database` property has been removed. Use the dedicated methods instead:

```swift
// Before
let data = try await supabase.database.from("users").select().execute()

// After
let data = try await supabase.from("users").select().execute()

// For RPC
let result = try await supabase.rpc("function_name", params: params)

// For schema
let client = supabase.schema("other_schema")
```

### Realtime Property

The `realtime` property (V1) has been removed. Use `realtimeV2` instead:

```swift
// Before
let channel = supabase.realtime.channel("room")

// After
let channel = supabase.realtimeV2.channel("room")
// Or use the convenience method
let channel = supabase.channel("room")
```

## Helpers Module

### ObservationToken

The `remove()` method has been renamed to `cancel()`:

```swift
// Before
token.remove()

// After
token.cancel()
```

## Summary

The v3 release focuses on:

1. **Cleaner naming**: Removing legacy "GoTrue" naming in favor of "Auth"
2. **Consistent APIs**: Standardizing parameter names and return types
3. **V2 consolidation**: Removing V1 Realtime in favor of V2
4. **Required logging**: Making logger configuration explicit

Most migrations involve straightforward renames and parameter updates. The most significant change is the complete removal of Realtime V1, which requires using the V2 APIs documented in the [RealtimeV2 Migration Guide](./RealtimeV2%20Migration%20Guide.md).
