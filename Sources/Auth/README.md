# Supabase Auth Module

The Auth module provides a comprehensive authentication system for Supabase applications with support for email/password authentication, OAuth providers, multi-factor authentication, and session management.

## Quick Start

```swift
import Supabase

// Initialize the client
let authClient = AuthClient(
  url: URL(string: "https://your-project.supabase.co/auth/v1")!,
  configuration: AuthClient.Configuration(
    localStorage: KeychainLocalStorage()
  )
)

// Check if user is logged in
if let user = await authClient.currentUser {
  print("Logged in as: \(user.email ?? "Unknown")")
}
```

## Authentication Methods

### Email/Password Authentication

```swift
// Sign up a new user
let authResponse = try await authClient.signUp(
  email: "user@example.com",
  password: "securepassword"
)

// Sign in existing user
let session = try await authClient.signIn(
  email: "user@example.com",
  password: "securepassword"
)

// Sign out
try await authClient.signOut()
```

### OAuth Authentication

```swift
// Sign in with OAuth provider
let session = try await authClient.signInWithOAuth(
  provider: .google,
  redirectTo: URL(string: "myapp://auth/callback")
)

// Handle OAuth callback
try await authClient.session(from: callbackURL)
```

### Magic Link Authentication

```swift
// Send magic link
try await authClient.signInWithOTP(
  email: "user@example.com",
  redirectTo: URL(string: "myapp://auth/callback")
)

// Handle magic link callback
try await authClient.session(from: magicLinkURL)
```

### Phone Authentication

```swift
// Send OTP to phone
try await authClient.signInWithOTP(
  phone: "+1234567890"
)

// Verify OTP
let session = try await authClient.verifyOTP(
  phone: "+1234567890",
  token: "123456",
  type: .sms
)
```

## Multi-Factor Authentication (MFA)

### Enrolling MFA

```swift
// Enroll a TOTP factor
let enrollment = try await authClient.mfa.enroll(
  params: MFAEnrollParams(
    factorType: .totp,
    friendlyName: "My Authenticator App"
  )
)

// Show QR code to user
// enrollment.totp.qrCode contains the QR code data
```

### Challenging and Verifying MFA

```swift
// Challenge the factor
let challenge = try await authClient.mfa.challenge(
  params: MFAChallengeParams(factorId: enrollment.id)
)

// Verify the MFA code
let verification = try await authClient.mfa.verify(
  params: MFAVerifyParams(
    factorId: enrollment.id,
    code: "123456"
  )
)
```

### Managing MFA Factors

```swift
// List all factors
let factors = try await authClient.mfa.listFactors()

// Unenroll a factor
try await authClient.mfa.unenroll(
  params: MFAUnenrollParams(factorId: factorId)
)
```

## Session Management

### Getting Current Session

```swift
// Get current session (automatically refreshes if needed)
let session = try await authClient.session

// Get current user
let user = try await authClient.user()

// Check if user is logged in (may be expired)
if let user = await authClient.currentUser {
  print("User: \(user.email ?? "No email")")
}
```

### Updating User Profile

```swift
// Update user attributes
let updatedUser = try await authClient.updateUser(
  attributes: UserAttributes(
    data: ["display_name": "John Doe"]
  )
)

// Update password
try await authClient.updateUser(
  attributes: UserAttributes(password: "newpassword")
)
```

### Listening to Auth State Changes

```swift
// Listen for authentication events
for await (event, session) in await authClient.authStateChanges {
  switch event {
  case .signedIn:
    print("User signed in")
  case .signedOut:
    print("User signed out")
  case .tokenRefreshed:
    print("Token refreshed")
  case .passwordRecovery:
    print("Password recovery initiated")
  case .mfaChallengeVerified:
    print("MFA challenge verified")
  }
}
```

## Password Recovery

```swift
// Send password recovery email
try await authClient.resetPasswordForEmail(
  "user@example.com",
  redirectTo: URL(string: "myapp://reset-password")
)

// Update password after recovery
try await authClient.updateUser(
  attributes: UserAttributes(password: "newpassword")
)
```

## OAuth Provider Configuration

### Supported Providers

```swift
// Available OAuth providers
let providers: [Provider] = [
  .apple,
  .azure,
  .bitbucket,
  .discord,
  .facebook,
  .github,
  .gitlab,
  .google,
  .keycloak,
  .linkedin,
  .notion,
  .twitch,
  .twitter,
  .slack,
  .spotify,
  .workos,
  .zoom
]

// Sign in with specific provider
let session = try await authClient.signInWithOAuth(
  provider: .google,
  redirectTo: URL(string: "myapp://auth/callback")
)
```

### Custom OAuth Configuration

```swift
// Sign in with custom OAuth provider
let session = try await authClient.signInWithOAuth(
  provider: .custom("my-provider"),
  redirectTo: URL(string: "myapp://auth/callback"),
  scopes: ["read", "write"]
)
```

## Administrative Functions

### User Management

```swift
// Get user by ID (requires service_role key)
let user = try await authClient.admin.getUserById(userId)

// Create a new user
let newUser = try await authClient.admin.createUser(
  attributes: AdminUserAttributes(
    email: "admin@example.com",
    password: "securepassword",
    emailConfirm: true
  )
)

// Update user attributes
let updatedUser = try await authClient.admin.updateUser(
  uid: userId,
  attributes: AdminUserAttributes(
    data: ["role": "admin"]
  )
)

// Delete a user
try await authClient.admin.deleteUser(id: userId)
```

### User Listing and Invitations

```swift
// List users with pagination
let users = try await authClient.admin.listUsers(
  params: AdminListUsersParams(
    page: 1,
    perPage: 50
  )
)

// Invite a user
let invitedUser = try await authClient.admin.inviteUserByEmail(
  email: "newuser@example.com",
  redirectTo: URL(string: "myapp://invite")
)
```

### Link Generation

```swift
// Generate a magic link
let link = try await authClient.admin.generateLink(
  params: GenerateLinkParams(
    type: .magicLink,
    email: "user@example.com",
    redirectTo: URL(string: "myapp://auth/callback")
  )
)
```

## Configuration

### Basic Configuration

```swift
let configuration = AuthClient.Configuration(
  localStorage: KeychainLocalStorage()
)

let authClient = AuthClient(
  url: URL(string: "https://myproject.supabase.co/auth/v1")!,
  configuration: configuration
)
```

### Advanced Configuration

```swift
let configuration = AuthClient.Configuration(
  headers: ["X-Custom-Header": "value"],
  flowType: .pkce,
  redirectToURL: URL(string: "myapp://auth/callback"),
  storageKey: "myapp_auth",
  localStorage: KeychainLocalStorage(),
  logger: MyCustomLogger(),
  autoRefreshToken: true
)
```

### Storage Options

```swift
// Secure storage (recommended for production)
let keychainStorage = KeychainLocalStorage()

// In-memory storage (useful for testing)
let memoryStorage = InMemoryLocalStorage()

// Custom storage implementation
class MyCustomStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws {
    // Custom storage logic
  }
  
  func retrieve(key: String) throws -> Data? {
    // Custom retrieval logic
  }
  
  func remove(key: String) throws {
    // Custom removal logic
  }
}
```

## Error Handling

```swift
do {
  let session = try await authClient.signIn(
    email: "user@example.com",
    password: "wrongpassword"
  )
} catch AuthError.invalidCredentials {
  print("Invalid email or password")
} catch AuthError.emailNotConfirmed {
  print("Please check your email and confirm your account")
} catch AuthError.tooManyRequests {
  print("Too many requests. Please try again later.")
} catch {
  print("Authentication failed: \(error)")
}
```

## URL Handling

### iOS App Delegate

```swift
func application(
  _ app: UIApplication,
  open url: URL,
  options: [UIApplication.OpenURLOptionsKey: Any]
) -> Bool {
  Task {
    do {
      try await supabase.auth.handle(url)
    } catch {
      print("Error handling URL: \(error)")
    }
  }
  return true
}
```

### SwiftUI

```swift
struct ContentView: View {
  var body: some View {
    SomeView()
      .onOpenURL { url in
        Task {
          do {
            try await supabase.auth.handle(url)
          } catch {
            print("Error handling URL: \(error)")
          }
        }
      }
  }
}
```

## Best Practices

### Security

1. **Never expose service_role key** in client-side code
2. **Use secure storage** (KeychainLocalStorage) for production apps
3. **Enable MFA** for sensitive applications
4. **Use PKCE flow** for mobile applications
5. **Validate redirect URLs** to prevent open redirect attacks

### Performance

1. **Use currentUser** for quick checks without network requests
2. **Use session** when you need a guaranteed valid session
3. **Enable autoRefreshToken** for seamless user experience
4. **Listen to authStateChanges** for real-time updates

### User Experience

1. **Handle all authentication states** (loading, success, error)
2. **Provide clear error messages** to users
3. **Implement proper loading states** during authentication
4. **Use appropriate storage** based on your app's needs

## Migration from v2

If you're migrating from Supabase Swift v2, see the [V3 Migration Guide](../../V3_MIGRATION_GUIDE.md) for detailed migration instructions.

## Troubleshooting

### Common Issues

1. **Session not persisting**: Ensure you're using a persistent storage implementation
2. **OAuth redirects not working**: Check your URL scheme configuration
3. **MFA not working**: Verify your authenticator app is properly configured
4. **Admin functions failing**: Ensure you're using the service_role key

### Debugging

```swift
// Enable logging
let configuration = AuthClient.Configuration(
  localStorage: KeychainLocalStorage(),
  logger: SupabaseLogger(level: .debug)
)
```

For more information, visit the [Supabase Auth documentation](https://supabase.com/docs/guides/auth).
