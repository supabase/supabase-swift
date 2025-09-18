# Migration Guide: Supabase Swift v2 → v3

This guide will help you migrate your project from Supabase Swift v2.x to v3.0.0.

## Overview

Supabase Swift v3.0.0 introduces several breaking changes designed to improve the developer experience, enhance type safety, and modernize the API. While there are breaking changes, most can be addressed with find-and-replace operations.

**Migration Complexity**: Medium-High
**Estimated Time**: 1-12 hours depending on project size
**Automation Available**: Partial (method renames, imports)

## Before You Begin

1. **Backup your project** - Commit all changes and create a backup
2. **Review dependencies** - Ensure all your dependencies support Swift 6.0+
3. **Update gradually** - Consider updating one module at a time
4. **Test thoroughly** - Run your test suite after each major change
5. **Check for deprecated usage** - Review compiler warnings for deprecated API usage

## Step-by-Step Migration

### 1. Update Package Dependencies

Update your `Package.swift` or Xcode project dependencies:

**Before (v2.x):**
```swift
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
```

**After (v3.x):**
```swift
.package(url: "https://github.com/supabase/supabase-swift.git", from: "3.0.0")
```

### 2. Requirements Update

v3.0.0 has updated minimum requirements:

**Before (v2.x):**
- iOS 13.0+ / macOS 10.15+ / tvOS 13+ / watchOS 6+ / visionOS 1+
- Xcode 15.3+
- Swift 5.10+

**After (v3.x):**
- iOS 13.0+ / macOS 10.15+ / tvOS 13+ / watchOS 6+ / visionOS 1+
- Xcode 16.0+
- Swift 6.0+

### 3. Deprecated API Removal

⚠️ **All deprecated APIs have been removed in v3.0.0**

If your code uses any deprecated APIs, you must update them before migrating:

#### Authentication Changes
```swift
// ❌ Removed - Update these before migrating to v3
GoTrueClient // Use AuthClient instead
GoTrueMFA // Use AuthMFA instead
GoTrueLocalStorage // Use AuthLocalStorage instead
GoTrueError // Use AuthError instead

// ❌ Removed error cases
AuthError.sessionNotFound // Use .sessionMissing
AuthError.pkce(.codeVerifierNotFound) // Use .pkceGrantCodeExchange(message:)
AuthError.invalidImplicitGrantFlowURL // Use .implicitGrantRedirect(message:)

// ❌ Removed deprecated struct
APIError // Use new AuthError.api(message:errorCode:underlyingData:underlyingResponse:)
```

#### PostgREST Changes
```swift
// ❌ Removed property
someFilterValue.queryValue // Use .rawValue instead
```

#### Storage Changes
```swift
// ❌ Removed - Use local encoder/decoder instead
JSONEncoder.defaultStorageEncoder // Create your own encoder
JSONDecoder.defaultStorageDecoder // Create your own decoder
```

#### Realtime Changes
```swift
// ❌ Removed methods
channel.broadcast(event: "test") // Use .broadcastStream(event:)
channel.subscribe() // Use .subscribeWithError()

// ❌ Removed property
token.remove() // Use .cancel()
```

#### UserCredentials Changes
```swift
// ❌ No longer public - Use internal equivalent or AuthClient methods
UserCredentials(...) // This type is now internal
```

### 4. Import Changes

Import statements remain the same:
```swift
import Supabase
import Auth
import Functions
import PostgREST
import Realtime
import Storage
```

### 3. Client Initialization

#### Basic Client Setup

**Before (v2.x):**
```swift
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "public-anon-key"
)
```

**After (v3.x):**
```swift
// ✅ Same basic initialization - no changes required
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "public-anon-key"
)
```

#### Advanced Configuration

**Before (v2.x):**
```swift
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "public-anon-key",
    options: SupabaseClientOptions(
        db: .init(schema: "public"),
        auth: .init(
            storage: MyCustomLocalStorage(),
            flowType: .pkce
        ),
        global: .init(
            headers: ["x-my-custom-header": "my-app-name"],
            session: URLSession.myCustomSession
        )
    )
)
```

**After (v3.x):**
```swift
// 🔄 Configuration structure updated - will be detailed in implementation
let client = SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "public-anon-key",
    options: SupabaseClientOptions(
        // Updated configuration structure
        // Details to be provided during implementation
    )
)
```

### 4. Authentication Changes

#### Sign In Methods

**Before (v2.x):**
```swift
// Email/Password
try await client.auth.signIn(email: "user@example.com", password: "password")

// OAuth
try await client.auth.signInWithOAuth(provider: .github)
```

**After (v3.x):**
```swift
// 🔄 Method signatures may be updated
// Specific changes to be documented during implementation
```

#### Session Management

**Before (v2.x):**
```swift
let session = client.auth.session
let user = client.auth.currentUser
```

**After (v3.x):**
```swift
// 🔄 Session access patterns may be updated
// Specific changes to be documented during implementation
```

### 5. Database (PostgREST) Changes

#### Basic Queries

**Before (v2.x):**
```swift
let users: [User] = try await client.database
    .from("users")
    .select()
    .execute()
    .value
```

**After (v3.x):**
```swift
// 🔄 Query builder API may be updated for better type safety
// Specific changes to be documented during implementation
```

#### Filtering and Ordering

**Before (v2.x):**
```swift
let users: [User] = try await client.database
    .from("users")
    .select()
    .eq("status", value: "active")
    .order("created_at", ascending: false)
    .execute()
    .value
```

**After (v3.x):**
```swift
// 🔄 Filter and order methods may have updated signatures
// Specific changes to be documented during implementation
```

### 6. Storage Changes

#### File Upload

**Before (v2.x):**
```swift
let data = "Hello, World!".data(using: .utf8)!
try await client.storage
    .from("documents")
    .upload(path: "hello.txt", file: data)
```

**After (v3.x):**
```swift
// 🔄 Upload API may be enhanced with better progress tracking
// Specific changes to be documented during implementation
```

#### File Download

**Before (v2.x):**
```swift
let data = try await client.storage
    .from("documents")
    .download(path: "hello.txt")
```

**After (v3.x):**
```swift
// 🔄 Download API may be updated
// Specific changes to be documented during implementation
```

### 7. Major Realtime Modernization

⚠️ **This is the largest breaking change in v3.0.0**

All Realtime V2 classes have been renamed to become the primary implementation:

#### Class and Property Renames

**Before (v2.x):**
```swift
import Realtime

// Old naming
let client = SupabaseClient(...)
let realtimeClient: RealtimeClientV2 = client.realtimeV2
let channel: RealtimeChannelV2 = realtimeClient.channel("test")
let message = RealtimeMessageV2(...)
```

**After (v3.x):**
```swift
import Realtime

// ✅ New naming (V2 suffix removed)
let client = SupabaseClient(...)
let realtimeClient: RealtimeClient = client.realtime  // ← realtimeV2 became realtime
let channel: RealtimeChannel = realtimeClient.channel("test")  // ← V2 suffix removed
let message = RealtimeMessage(...)  // ← V2 suffix removed
```

#### Find and Replace Operations

Use these find-and-replace operations to update your code:

```bash
# Find and replace in your codebase:
RealtimeClientV2 → RealtimeClient
RealtimeChannelV2 → RealtimeChannel
RealtimeMessageV2 → RealtimeMessage
PushV2 → Push
.realtimeV2 → .realtime
```

#### Updated Channel Subscriptions

**Before (v2.x):**
```swift
let channel = client.realtimeV2.channel("public:users")
await channel.on(.postgresChanges(event: .all, schema: "public", table: "users")) { payload in
    print("Received change: \\(payload)")
}
try await channel.subscribeWithError() // ✅ This method is still available
```

**After (v3.x):**
```swift
// ✅ Same API, just different property name
let channel = client.realtime.channel("public:users")  // ← realtimeV2 became realtime
await channel.on(.postgresChanges(event: .all, schema: "public", table: "users")) { payload in
    print("Received change: \\(payload)")
}
try await channel.subscribeWithError() // ✅ Same method
```

### 8. Real-time API Updates

#### Removed Deprecated Methods

**Before (v2.x):**
```swift
// ❌ These deprecated methods were removed
channel.subscribe() // Use subscribeWithError() instead
channel.broadcast(event: "test") // Use broadcastStream(event:) instead
```

**After (v3.x):**
```swift
// ✅ Use the non-deprecated equivalents
try await channel.subscribeWithError() // Throws errors instead of silently failing
let stream = channel.broadcastStream(event: "test") // Returns AsyncStream
```

### 8. Functions Changes

#### Function Client Initialization (Thread Safety)
FunctionsClient is now an actor for thread safety:

**Before (v2.x):**
```swift
let functionsClient = FunctionsClient(
    url: url,
    headers: ["key": "value"],  // [String: String]
    region: "us-east-1"         // String
)
```

**After (v3.x):**
```swift
let functionsClient = FunctionsClient(
    url: url,
    headers: HTTPHeaders([("key", "value")]),  // HTTPHeaders type
    region: FunctionRegion.usEast1             // FunctionRegion type
)
```

#### Function Invoke Options
The options API now uses a type-safe enum for body handling:

**Before (v2.x):**
```swift
let options = FunctionInvokeOptions()
options.body = myData  // Simple Data property
```

**After (v3.x):**
```swift
let options = FunctionInvokeOptions()

// Type-safe body options using FunctionInvokeSupportedBody enum:
options.body = .data(myData)                    // for binary data
options.body = .string("my string")             // for text data
options.body = .encodable(myObject)             // for JSON objects
options.body = .fileURL(fileURL)                // for file uploads
options.body = .multipartFormData { formData in // for form uploads
    formData.append(data, withName: "file", fileName: "test.txt", mimeType: "text/plain")
}
```

#### Enhanced Upload Support
v3.x adds native support for file and multipart uploads:

```swift
// File upload
let result = try await functionsClient.invoke("upload-handler") { options in
    options.body = .fileURL(URL(fileURLWithPath: "/path/to/file.pdf"))
}

// Multipart form data
let result = try await functionsClient.invoke("form-handler") { options in
    options.body = .multipartFormData { formData in
        formData.append("value1".data(using: .utf8)!, withName: "field1")
        formData.append(imageData, withName: "image", fileName: "photo.jpg", mimeType: "image/jpeg")
    }
}
```

### 9. Error Handling Changes

#### Error Types

**Before (v2.x):**
```swift
do {
    let result = try await client.auth.signIn(email: email, password: password)
} catch let error as AuthError {
    // Handle auth-specific error
} catch {
    // Handle general error
}
```

**After (v3.x):**
```swift
// 🔄 Error types may be consolidated and improved
// Specific changes to be documented during implementation
```

## Common Migration Patterns

### Find and Replace Operations

When specific method changes are implemented, you can use these find-and-replace patterns:

```bash
# Example patterns (to be updated during implementation)
# find: "oldMethodName"
# replace: "newMethodName"
```

### Automated Migration Tools

We may provide migration scripts for common patterns:

```bash
# Future migration script (if developed)
# swift run migration-tool v2-to-v3 --path ./Sources
```

## Testing Your Migration

### 1. Compile-time Checks
```bash
swift build
```

### 2. Update Test Code
You may need to update test-specific code:

```swift
// Update MFA enrollment in tests
// Before:
params: MFAEnrollParams(issuer: "supabase.com", friendlyName: "test")

// After:
params: MFATotpEnrollParams(issuer: "supabase.com", friendlyName: "test")

// Update PostgREST filters in tests
// Before:
.ilike("email", value: "pattern%")

// After:
.ilike("email", pattern: "pattern%")

// Remove deprecated properties from user attributes
// Before:
UserAttributes(email: "...", emailChangeToken: "...")

// After:
UserAttributes(email: "...")
```

### 3. Run Your Test Suite
```bash
swift test
```

### 4. Integration Testing
Test your app thoroughly, especially:
- Authentication flows
- Database operations
- Real-time subscriptions
- File uploads/downloads
- Edge function calls

## Troubleshooting

### Common Issues

1. **Compilation Errors**
   - Check method signatures against the new API
   - Update import statements if needed
   - Review configuration options

2. **Runtime Errors**
   - Test authentication flows
   - Verify database queries
   - Check real-time subscriptions

3. **Performance Issues**
   - Review new configuration options
   - Check for deprecated patterns
   - Update to new recommended approaches

### Getting Help

- **Documentation**: [https://supabase.com/docs/reference/swift](https://supabase.com/docs/reference/swift)
- **GitHub Issues**: [https://github.com/supabase/supabase-swift/issues](https://github.com/supabase/supabase-swift/issues)
- **Community**: [Supabase Discord](https://discord.supabase.com)

## Migration Checklist

Use this checklist to track your migration progress:

- [ ] **Pre-migration**
  - [ ] Backup project
  - [ ] Review current dependencies
  - [ ] Plan migration approach

- [ ] **Dependencies**
  - [ ] Update Package.swift or Xcode project
  - [ ] Update minimum Swift/Xcode versions
  - [ ] Resolve any dependency conflicts
  - [ ] Update minimum platform versions if needed

- [ ] **Deprecated API Removal**
  - [ ] Replace all GoTrue* type aliases with Auth* equivalents
  - [ ] Update deprecated AuthError cases
  - [ ] Replace queryValue with rawValue
  - [ ] Replace deprecated storage encoder/decoder usage
  - [ ] Update deprecated realtime methods

- [ ] **Client Initialization**
  - [ ] Update basic client setup (if needed)
  - [ ] Migrate advanced configuration options
  - [ ] Test client initialization

- [ ] **Authentication**
  - [ ] Remove deprecated error handling
  - [ ] Update sign-in methods (if affected)
  - [ ] Migrate session management code
  - [ ] Update MFA implementation (if used)
  - [ ] Test authentication flows

- [ ] **Database Operations**
  - [ ] Update query builder usage
  - [ ] Migrate filtering and ordering
  - [ ] Update insert/update/delete operations
  - [ ] Test database operations

- [ ] **Storage**
  - [ ] Replace deprecated encoder/decoder usage
  - [ ] Update file upload code
  - [ ] Update file download code
  - [ ] Migrate progress tracking (if used)
  - [ ] Test storage operations

- [ ] **Real-time (Major Changes)**
  - [ ] Replace RealtimeClientV2 with RealtimeClient
  - [ ] Replace RealtimeChannelV2 with RealtimeChannel
  - [ ] Replace RealtimeMessageV2 with RealtimeMessage
  - [ ] Update .realtimeV2 to .realtime
  - [ ] Replace deprecated subscribe() with subscribeWithError()
  - [ ] Replace deprecated broadcast() with broadcastStream()
  - [ ] Update channel subscriptions
  - [ ] Migrate presence features (if used)
  - [ ] Test real-time functionality

- [ ] **Functions**
  - [ ] Update function invocation code
  - [ ] Update parameter passing
  - [ ] Test edge function calls

- [ ] **Error Handling**
  - [ ] Update error catching patterns
  - [ ] Review error handling logic
  - [ ] Test error scenarios

- [ ] **Testing**
  - [ ] Run compile-time checks
  - [ ] Execute test suite
  - [ ] Perform integration testing
  - [ ] Test in production-like environment

- [ ] **Documentation**
  - [ ] Update internal documentation
  - [ ] Update code comments
  - [ ] Document any workarounds

## Rollback Plan

If you encounter issues during migration:

1. **Immediate Rollback**
   ```bash
   git checkout previous-working-commit
   ```

2. **Partial Rollback**
   - Revert to v2.x dependency
   - Keep code changes that are compatible
   - Plan incremental migration

3. **Gradual Migration**
   - Migrate one module at a time
   - Test each module thoroughly
   - Keep v2.x and v3.x in parallel (if possible)

---

*This migration guide will be updated as v3 development progresses.*
*Last Updated: 2025-09-18*