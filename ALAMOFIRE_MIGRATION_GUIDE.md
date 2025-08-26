# Supabase Swift SDK - Alamofire Migration Guide

This guide covers the breaking changes introduced when migrating the Supabase Swift SDK from URLSession to Alamofire for HTTP networking.

## Overview

The migration to Alamofire introduces breaking changes in how modules are initialized and configured. The primary change is replacing custom `FetchHandler` closures with Alamofire `Session` instances across all modules.

## Breaking Changes by Module

### 🔴 AuthClient

**Before (URLSession-based):**
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

**After (Alamofire-based):**
```swift
let authClient = AuthClient(
  url: authURL,  
  headers: headers,
  localStorage: MyLocalStorage(),
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

**Key Changes:**
- ❌ **Removed**: `fetch: FetchHandler` parameter
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)
- The `FetchHandler` typealias is still present for backward compatibility but is no longer used

### 🔴 FunctionsClient

**Before (URLSession-based):**
```swift
let functionsClient = FunctionsClient(
  url: functionsURL,
  headers: headers,
  fetch: { request in
    try await URLSession.shared.data(for: request)
  }
)
```

**After (Alamofire-based):**
```swift
let functionsClient = FunctionsClient(
  url: functionsURL,
  headers: headers,
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

**Key Changes:**
- ❌ **Removed**: `fetch: FetchHandler` parameter  
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)

### 🔴 PostgrestClient

**Before (URLSession-based):**
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

**After (Alamofire-based):**
```swift
let postgrestClient = PostgrestClient(
  url: databaseURL,
  schema: "public", 
  headers: headers,
  session: Alamofire.Session.default  // ← Now requires Alamofire.Session
)
```

**Key Changes:**
- ❌ **Removed**: `fetch: FetchHandler` parameter
- ✅ **Added**: `session: Alamofire.Session` parameter (defaults to `.default`)
- The `FetchHandler` typealias is still present for backward compatibility but is no longer used

### 🔴 StorageClientConfiguration

**Before (URLSession-based):**
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

**After (Alamofire-based):**
```swift
let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: Alamofire.Session.default  // ← Now directly uses Alamofire.Session
)
```

**Key Changes:**
- ❌ **Removed**: `StorageHTTPSession` wrapper class
- ✅ **Changed**: `session` parameter now expects `Alamofire.Session` directly
- Upload functionality is now handled internally by Alamofire

### 🟡 SupabaseClient (Indirect Changes)

The `SupabaseClient` initialization remains the same, but internally it now passes Alamofire sessions to the underlying modules:

**No changes to public API:**
```swift
// This remains the same
let supabase = SupabaseClient(
  supabaseURL: supabaseURL,
  supabaseKey: supabaseKey
)
```

However, if you were customizing individual modules through options, you now need to provide Alamofire sessions:

**Before:**
```swift
let options = SupabaseClientOptions(
  db: SupabaseClientOptions.DatabaseOptions(
    // Custom fetch handlers were used internally
  )
)
```

**After:**
```swift
// Custom session configuration now required for advanced customization
let customSession = Session(configuration: .default)
// Then pass the session when creating individual clients
```

## Migration Steps

### 1. Update Package Dependencies

Ensure your `Package.swift` includes Alamofire:

```swift
dependencies: [
  .package(url: "https://github.com/supabase/supabase-swift", from: "3.0.0"),
  // Alamofire is now included as a transitive dependency
]
```

### 2. Update Import Statements

If you were using individual modules, you may need to import Alamofire:

```swift
import Supabase
import Alamofire  // ← Add if using custom sessions
```

### 3. Replace FetchHandler with Alamofire.Session

For each module initialization, replace `fetch` parameters with `session` parameters:

```swift
// Replace this pattern:
fetch: { request in
  try await URLSession.shared.data(for: request)
}

// With this:
session: .default
// or
session: myCustomSession
```

### 4. Custom Session Configuration

If you need custom networking behavior (interceptors, retry logic, etc.), create a custom Alamofire session:

```swift
// Custom session with retry logic
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

### 5. Update Storage Upload Handling

If you were customizing storage upload behavior, now configure it through the Alamofire session:

```swift
// Before: Custom StorageHTTPSession
let storageSession = StorageHTTPSession(
  fetch: customFetch,
  upload: customUpload
)

// After: Custom Alamofire session with upload configuration
let session = Session(configuration: customConfiguration)
let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: session
)
```

## Advanced Configuration

### Custom Interceptors

Alamofire allows you to add request/response interceptors:

```swift
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
}

let session = Session(interceptor: AuthInterceptor())
```

### Background Upload/Download Support

Take advantage of Alamofire's background session support:

```swift
let backgroundSession = Session(
  configuration: .background(withIdentifier: "com.myapp.background")
)

let storageConfig = StorageClientConfiguration(
  url: storageURL,
  headers: headers,
  session: backgroundSession
)
```

### Progress Tracking

Monitor upload/download progress with Alamofire:

```swift
// This functionality is now built into the modules
// and can be accessed through Alamofire's progress APIs
```

## Error Handling Changes

Error handling patterns have been updated to work with Alamofire's error types. Most error cases are handled internally, but you may encounter `AFError` types in edge cases.

## Performance Considerations

The migration to Alamofire brings several performance improvements:
- Better connection pooling
- Optimized request/response handling  
- Built-in retry mechanisms
- Streaming support for large files

## Troubleshooting

### Common Issues

1. **"Cannot find 'Session' in scope"**
   - Add `import Alamofire` to your file
   
2. **"Cannot convert value of type 'FetchHandler' to expected argument type 'Session'"**
   - Replace `fetch:` parameter with `session:` and provide an Alamofire session

3. **"StorageHTTPSession not found"**
   - Replace with direct `Alamofire.Session` usage

### Testing Changes

Update your tests to work with Alamofire sessions instead of custom fetch handlers:

```swift
// Before: Mock fetch handler
let mockFetch: FetchHandler = { _ in
  return (mockData, mockResponse)
}

// After: Mock Alamofire session or use dependency injection
let mockSession = // Configure mock session
```

## Getting Help

If you encounter issues during migration:

1. Check that all `fetch:` parameters are replaced with `session:`
2. Ensure you're importing Alamofire when using custom sessions
3. Review your custom networking code for compatibility with Alamofire patterns
4. Consult the [Alamofire documentation](https://github.com/Alamofire/Alamofire) for advanced configuration options

For further assistance, please open an issue in the [supabase-swift repository](https://github.com/supabase/supabase-swift/issues).