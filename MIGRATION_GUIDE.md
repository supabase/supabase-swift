# Supabase Swift SDK - v2.x to v3.x Migration Guide

This guide covers the breaking changes when migrating from Supabase Swift SDK v2.x to v3.x.

## Overview

Version 3.0 introduces breaking changes in how HTTP networking is handled across all modules. The SDK has migrated from URLSession-based custom `FetchHandler` closures to Alamofire `Session` instances. This change affects the initialization of `AuthClient`, `FunctionsClient`, `PostgrestClient`, and `StorageClient`.

**Key Change**: All modules now require an `Alamofire.Session` parameter instead of a custom `fetch: FetchHandler` closure.

## Quick Migration Checklist

- [ ] Replace all `fetch: FetchHandler` parameters with `session: Alamofire.Session`
- [ ] Remove custom `StorageHTTPSession` wrappers (use `Alamofire.Session` directly)
- [ ] Add `import Alamofire` if using custom session configuration
- [ ] Update tests to mock Alamofire sessions instead of fetch handlers
- [ ] Remove any `FetchHandler` typealias references from your code
- [ ] Verify your dependency manager includes Alamofire (automatically included as transitive dependency)

## Breaking Changes by Module

### AuthClient

#### Parameter Change

**v2.x (URLSession-based):**
```swift
let authClient = AuthClient(
  url: authURL,
  headers: headers,
  localStorage: MyLocalStorage(),
  fetch: { request in
    try await URLSession.shared.data(for: request)
  }
)
```

**v3.x (Alamofire-based):**
```swift
let authClient = AuthClient(
  url: authURL,  
  headers: headers,
  localStorage: MyLocalStorage(),
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

#### Migration Pattern

**Action Required**: Replace the `fetch` parameter with `session`.

```swift
// Remove this:
fetch: { request in
  try await URLSession.shared.data(for: request)
}

// Add this:
session: .default  // or your custom Alamofire.Session instance
```

#### What Changed

- ❌ **Removed**: `fetch: FetchHandler` parameter
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)
- ℹ️ **Note**: The `FetchHandler` typealias remains for backward compatibility but is not used

---

### FunctionsClient

#### Parameter Change

**v2.x (URLSession-based):**
```swift
let functionsClient = FunctionsClient(
  url: functionsURL,
  headers: headers,
  fetch: { request in
    try await URLSession.shared.data(for: request)
  }
)
```

**v3.x (Alamofire-based):**
```swift
let functionsClient = FunctionsClient(
  url: functionsURL,
  headers: headers,
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

#### Migration Pattern

Same as AuthClient - replace `fetch` parameter with `session`.

#### What Changed

- ❌ **Removed**: `fetch: FetchHandler` parameter
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)

---

### PostgrestClient

#### Parameter Change

**v2.x (URLSession-based):**
```swift
let postgrestClient = PostgrestClient(
  url: databaseURL,
  schema: "public",
  headers: headers,
  fetch: { request in
    try await URLSession.shared.data(for: request)
  }
)
```

**v3.x (Alamofire-based):**
```swift
let postgrestClient = PostgrestClient(
  url: databaseURL,
  schema: "public", 
  headers: headers,
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

#### Migration Pattern

Same as AuthClient - replace `fetch` parameter with `session`.

#### What Changed

- ❌ **Removed**: `fetch: FetchHandler` parameter
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)
- ℹ️ **Note**: The `FetchHandler` typealias remains for backward compatibility but is not used

---

### StorageClientConfiguration

#### Parameter Change

**v2.x (URLSession-based):**
```swift
let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: StorageHTTPSession(
    fetch: { request in
      try await URLSession.shared.data(for: request)
    },
    upload: { request, data in
      try await URLSession.shared.upload(for: request, from: data)
    }
  )
)
```

**v3.x (Alamofire-based):**
```swift
let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: Alamofire.Session.default  // ← Now directly uses Alamofire.Session
)
```

#### Migration Pattern

**Action Required**: Remove `StorageHTTPSession` wrapper and pass `Alamofire.Session` directly.

```swift
// Remove this wrapper:
session: StorageHTTPSession(
  fetch: { ... },
  upload: { ... }
)

// Replace with:
session: .default  // or your custom Alamofire.Session instance
```

#### What Changed

- ❌ **Removed**: `StorageHTTPSession` wrapper class entirely
- ✅ **Changed**: `session` parameter now expects `Alamofire.Session` directly
- ℹ️ **Note**: Upload functionality is now handled internally by Alamofire

---

### SupabaseClient

#### Impact Level: Low (Indirect Changes)

The `SupabaseClient` initialization API remains unchanged for basic usage. However, if you were customizing individual modules through options, you now need to provide Alamofire sessions.

#### Basic Usage (No Changes Required)

```swift
// v2.x and v3.x - identical
let supabase = SupabaseClient(
  supabaseURL: supabaseURL,
  supabaseKey: supabaseKey
)
```

#### Advanced Customization

If you were customizing individual modules through options:

**v2.x:**
```swift
let options = SupabaseClientOptions(
  db: SupabaseClientOptions.DatabaseOptions(
    // Custom fetch handlers were used internally
  )
)
```

**v3.x:**
```swift
// Create custom Alamofire session
let customSession = Session(configuration: .default)

// Pass the session when creating individual clients
// (consult individual module documentation for specific implementation)
```

---

## Step-by-Step Migration Guide

Follow these steps in order to migrate your codebase from v2.x to v3.x.

### Step 1: Update Package Dependencies

Update your dependency manager to use Supabase Swift SDK v3.0 or later.

**Swift Package Manager (`Package.swift`):**
```swift
dependencies: [
  .package(url: "https://github.com/supabase/supabase-swift", from: "3.0.0")
]
```

**Note**: Alamofire is included as a transitive dependency - you don't need to add it explicitly.

**CocoaPods (`Podfile`):**
```ruby
pod 'Supabase', '~> 3.0'
```

### Step 2: Add Import Statements

If using custom session configuration, add Alamofire import:

```swift
import Supabase
import Alamofire  // ← Required only if configuring custom sessions
```

### Step 3: Replace `fetch` with `session` Parameters

Locate all client initializations and apply the following transformation:

**Pattern to Find:**
```swift
fetch: { request in
  try await URLSession.shared.data(for: request)
}
```

**Replace With:**
```swift
session: .default
```

**Or with custom session:**
```swift
session: myCustomAlamofireSession
```

### Step 4: Remove StorageHTTPSession Wrappers

For `StorageClientConfiguration`, remove the `StorageHTTPSession` wrapper:

**Pattern to Find:**
```swift
session: StorageHTTPSession(
  fetch: { request in ... },
  upload: { request, data in ... }
)
```

**Replace With:**
```swift
session: .default
```

### Step 5: Configure Custom Sessions (Optional)

If you need custom networking behavior (interceptors, retry logic, timeouts, etc.), create a custom Alamofire session:

```swift
// Example: Custom session with retry logic
let session = Session(
  configuration: .default,
  interceptor: RetryRequestInterceptor()
)

let authClient = AuthClient(
  url: authURL,
  localStorage: MyLocalStorage(),
  session: session
)
```

### Step 6: Update Tests

Replace mock fetch handlers with mock Alamofire sessions:

**v2.x Test Code:**
```swift
let mockFetch: FetchHandler = { request in
  return (mockData, mockResponse)
}

let client = AuthClient(
  url: testURL,
  localStorage: MockStorage(),
  fetch: mockFetch
)
```

**v3.x Test Code:**
```swift
// Use dependency injection or configure a mock Alamofire session
let mockSession = Session(/* mock configuration */)

let client = AuthClient(
  url: testURL,
  localStorage: MockStorage(),
  session: mockSession
)
```

---

## Advanced Configuration Examples

### Custom Request Interceptors

Use Alamofire interceptors to modify requests or handle authentication:

```swift
import Alamofire

class AuthInterceptor: RequestInterceptor {
  func adapt(
    _ urlRequest: URLRequest,
    for session: Session,
    completion: @escaping (Result<URLRequest, Error>) -> Void
  ) {
    var request = urlRequest
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    completion(.success(request))
  }

  func retry(
    _ request: Request,
    for session: Session,
    dueTo error: Error,
    completion: @escaping (RetryResult) -> Void
  ) {
    // Implement custom retry logic
    completion(.doNotRetry)
  }
}

let session = Session(interceptor: AuthInterceptor())
let authClient = AuthClient(url: authURL, localStorage: storage, session: session)
```

### Custom Timeouts and Configuration

Configure request timeouts and other URLSessionConfiguration properties:

```swift
let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 30
configuration.timeoutIntervalForResource = 300

let session = Session(configuration: configuration)
let postgrestClient = PostgrestClient(url: dbURL, headers: headers, session: session)
```

### Background Upload/Download Support

For long-running transfers (requires app delegate configuration):

```swift
let backgroundConfig = URLSessionConfiguration.background(
  withIdentifier: "com.myapp.supabase.background"
)
let backgroundSession = Session(configuration: backgroundConfig)

let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: backgroundSession
)
```

### Custom Certificate Pinning

Enhance security with certificate pinning:

```swift
let evaluators = [
  "your-project.supabase.co": PinnedCertificatesTrustEvaluator()
]
let trustManager = ServerTrustManager(evaluators: evaluators)
let session = Session(serverTrustManager: trustManager)
```

---

## Changes to Error Handling

Error handling patterns have been updated. Alamofire errors (`AFError`) may surface in edge cases, but the SDK handles most networking errors internally and transforms them into Supabase-specific error types.

**What You Need to Know:**
- Most applications won't need to handle `AFError` directly
- Existing error handling for Supabase errors continues to work
- Network-level errors are still caught and reported through standard SDK error types

---

## Performance Benefits

Migrating to Alamofire provides several performance and reliability improvements:

- **Better Connection Pooling**: More efficient HTTP/2 and connection reuse
- **Optimized Request/Response Handling**: Reduced overhead for concurrent requests
- **Built-in Retry Mechanisms**: Configurable retry logic for failed requests
- **Streaming Support**: Improved handling of large file uploads/downloads
- **Background Transfers**: Native support for background upload/download tasks

---

## Troubleshooting Common Issues

### Compilation Errors

#### Error: "Cannot find 'Session' in scope"

**Solution**: Add Alamofire import at the top of your file:
```swift
import Alamofire
```

#### Error: "Cannot convert value of type 'FetchHandler' to expected argument type 'Session'"

**Solution**: Replace the `fetch:` parameter with `session:`:
```swift
// ❌ Old
fetch: { request in try await URLSession.shared.data(for: request) }

// ✅ New
session: .default
```

#### Error: "Type 'StorageHTTPSession' not found"

**Solution**: Remove `StorageHTTPSession` wrapper and pass `Alamofire.Session` directly:
```swift
// ❌ Old
session: StorageHTTPSession(fetch: ..., upload: ...)

// ✅ New
session: .default
```

#### Error: "Extra argument 'fetch' in call"

**Solution**: The `fetch` parameter has been removed. Replace with `session`:
```swift
// ❌ Old
AuthClient(url: url, headers: headers, fetch: myFetchHandler)

// ✅ New
AuthClient(url: url, headers: headers, session: .default)
```

### Runtime Issues

#### Issue: Unexpected network behavior or timeouts

**Solution**: Check if you need custom URLSessionConfiguration:
```swift
let configuration = URLSessionConfiguration.default
configuration.timeoutIntervalForRequest = 60
let session = Session(configuration: configuration)
```

#### Issue: Background uploads not working

**Solution**: Ensure proper background session configuration and app delegate setup:
```swift
let backgroundConfig = URLSessionConfiguration.background(
  withIdentifier: "com.myapp.supabase"
)
let session = Session(configuration: backgroundConfig)
```

### Testing Issues

#### Issue: Tests failing after migration

**Solution**: Update test mocks to use Alamofire sessions. Consider using protocol-based dependency injection for better testability:

```swift
// v3.x test approach
let mockSession = Session(/* configure for testing */)
let client = AuthClient(url: testURL, localStorage: mockStorage, session: mockSession)
```

---

## Additional Resources

- **Supabase Swift SDK v3.x Documentation**: [https://supabase.com/docs/reference/swift](https://supabase.com/docs/reference/swift)
- **Alamofire Documentation**: [https://github.com/Alamofire/Alamofire](https://github.com/Alamofire/Alamofire)
- **Report Issues**: [https://github.com/supabase/supabase-swift/issues](https://github.com/supabase/supabase-swift/issues)

---

## Summary

**Key Takeaway**: Replace all `fetch: FetchHandler` parameters with `session: Alamofire.Session` across `AuthClient`, `FunctionsClient`, `PostgrestClient`, and `StorageClientConfiguration`. Remove `StorageHTTPSession` wrappers entirely.

For most applications, this is a straightforward parameter replacement. Advanced use cases may benefit from custom Alamofire session configuration for interceptors, timeouts, and background transfers.