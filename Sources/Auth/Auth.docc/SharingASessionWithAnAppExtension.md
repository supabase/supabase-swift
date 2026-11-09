# Sharing a session with an app extension or widget

Let a widget, share extension, or App Clip use the session of your app.

## Overview

An app and its extensions run in different processes. They share a session when they read and
write the same Keychain item. This article shows the supported setup: one Keychain access group
for every target, and one process that refreshes the session.

### Add the Keychain access group

1. In Xcode, add the **Keychain Sharing** capability to the app target and to every extension
   target.
2. Give every target the same group, for example `com.example.shared`. Xcode writes it to the
   `keychain-access-groups` entitlement as `$(AppIdentifierPrefix)com.example.shared`.

Once you pass an access group, ``KeychainStorage`` reads and writes only that group. A session that
an earlier version of your app stored without a group sits in the group of the app itself, so the
new storage does not find it. Each existing user signs in again once, after the update.

The `$(AppIdentifierPrefix)` build setting expands in entitlements and in `Info.plist`, but not
in Swift code. ``KeychainStorage/init(service:accessGroup:accessibility:synchronizable:useDataProtectionKeychain:)``
needs the resolved name, which looks like `ABCDE12345.com.example.shared`. Pass it through an
`Info.plist` key that every target has:

```xml
<key>KeychainAccessGroup</key>
<string>$(AppIdentifierPrefix)com.example.shared</string>
```

### Create the same storage in every target

Put the client factory in code that all targets compile, such as a shared framework. Use the
same project URL, so the clients derive the same storage key, and the same access group.

```swift
func makeSupabaseClient(autoRefresh: AuthClient.AutoRefreshPolicy) -> SupabaseClient {
  // A missing key would give `nil`, and `nil` means the default group. The app and the
  // extension would then stop sharing, with no error.
  guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
  else { fatalError("Add KeychainAccessGroup to the Info.plist of every target.") }

  return SupabaseClient(
    supabaseURL: URL(string: "https://xyzcompany.supabase.co")!,
    supabaseKey: "your-publishable-key",
    configuration: .init(
      auth: .init(
        storage: KeychainStorage(accessGroup: accessGroup),
        autoRefresh: autoRefresh
      )
    )
  )
}

// In the app:
let supabase = makeSupabaseClient(autoRefresh: .automatic)

// In the extension:
let supabase = makeSupabaseClient(autoRefresh: .disabled)
```

### Refresh in one process only

A refresh token rotates: the server accepts each one once. When two processes refresh the same
token, one of them uses a token that the other already spent, and the server can revoke the
session. Let the app refresh, and set ``AuthClient/AutoRefreshPolicy/disabled`` in the extension.

Under that policy the extension:

- Reads the stored session once, when its client is created. It does not see a change that the app
  makes later. Create the client when the extension starts, and do not keep it for hours.
- Never refreshes. ``AuthClient/session()`` returns the stored session until it expires, then
  throws an ``AuthError`` of kind ``AuthError/Kind-swift.struct/refreshDisabled``.

An access token lives for one hour by default, so a widget can find an expired session. Keep the
stored session fresh from the app. Call ``AuthClient/refreshSessionIfNeeded()`` from a
`BGAppRefreshTask` handler. It refreshes when less than half of the lifetime is left, and does
nothing otherwise.

```swift
func handle(task: BGAppRefreshTask) {
  Task {
    _ = try? await supabase.auth.refreshSessionIfNeeded()
    task.setTaskCompleted(success: true)
  }
}
```

In the extension, catch the cases that need the user:

```swift
do {
  let session = try await supabase.auth.session()
  show(user: session.user)
} catch let error as AuthError where error.kind == .sessionMissing {
  showSignedOut()
} catch let error as AuthError where error.kind == .refreshDisabled {
  showOpenTheApp()
} catch let error as AuthError where error.kind == .storageUnavailable {
  // The device has not been unlocked since it restarted. Try again later.
  showPlaceholder()
}
```

``AuthError/Kind-swift.struct/storageUnavailable`` is not "signed out". The Keychain cannot be read
yet, so show a placeholder and try again.

The extension also does not sign in or out. Do that in the app. A client that the extension
creates later finds no session and reports ``AuthStatus/signedOut(_:)``.

### Keep widgets readable while the device is locked

``KeychainStorage`` uses ``KeychainStorage/Accessibility-swift.enum/afterFirstUnlockThisDeviceOnly``
by default. A widget can read the session after the first unlock since the device restarted, even
when the screen is locked again, and the session never moves to another device. Do not switch to
`.whenUnlocked` for a widget: its timeline refresh can run while the device is locked, and the read
would fail.

### Fix errSecMissingEntitlement

When a Keychain call fails with `errSecMissingEntitlement` (-34018), Auth throws an
``AuthError`` of kind ``AuthError/Kind-swift.struct/storageMisconfigured``. Check these causes:

- The target lacks the **Keychain Sharing** capability. Add it to the app and to the extension.
- The group that you pass is not in the entitlements of the target. Compare the string
  character by character with the `keychain-access-groups` entry. A typo, or a name that still
  holds the unresolved text `$(AppIdentifierPrefix)`, fails the same way.
- The build is not signed. An unsigned macOS tool or a test bundle has no entitlements. Use
  ``InMemoryAuthStorage`` there.
- The provisioning profile does not include the group. Regenerate it after you add the capability.

### watchOS has its own Keychain

An access group shares items between apps on one device. A watch app runs on another device, with
its own Keychain, so it cannot read the session of the iPhone app.

Sign the user in on the watch, or send the tokens from the iPhone and call
``AuthClient/importSession(accessToken:refreshToken:)`` on the watch. See
<doc:ImportingASessionOnTvOS>. The watch then owns that session and refreshes it itself. The
iPhone must not keep using the same session, because two devices that refresh one rotating token
race. Give the watch its own session, or stop using the session on the iPhone.
