# OAuth 2.1 Authorization Server (consent/grants) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add client support for the OAuth 2.1 authorization-server consent/grants API (`SDK-1295`) — approving/denying pending authorization requests, listing and revoking grants — as a new `AuthClient.oauthServer` namespace.

**Architecture:** New `AuthOAuthServer` struct following the existing `AuthMFA`/`AuthAdminOAuth` namespace pattern (dependency-injected via `clientID`, HTTP via `api.authorizedExecute`). New `Codable` types in `Types.swift`. New `ErrorCode` entries in `AuthError.swift` — no new error cases, the existing generic `AuthError.api` handles everything.

**Tech Stack:** Swift 6, XCTest + Mocker (unit), XCTest + local Supabase CLI (integration). Design doc: `docs/superpowers/specs/2026-07-10-oauth-authorization-server-design.md`.

## Global Constraints

- New public API must have DocC doc comments (repo convention, see AGENTS.md).
- 2-space indentation; run `./scripts/format.sh` before each commit that touches Swift source.
- `authorizationId` is `String` (32-char base32 token, NOT a UUID) — confirmed against `supabase/auth` Go source (`crypto.SecureAlphanumeric(32)`), do not "fix" this to `UUID`.
- `OAuthAuthorizationClient.id` and `OAuthAuthorizationUser.id` ARE `UUID` (map to real `uuid` DB columns).
- `uri`/`logoUri` are `URL?` — Go's `ClientDetailsResponse` fields are non-pointer strings tagged `,omitempty`, so absence means a missing JSON key, not `""`. No custom empty-string handling needed.
- `Types.swift`'s decoder uses `.convertFromSnakeCase` (`Sources/Auth/Defaults.swift:20`) — only add explicit `CodingKeys` where the auto conversion doesn't produce the desired Swift name (this applies to `OAuthRedirect.redirectURL`, whose JSON key `redirect_url` would otherwise auto-convert to `redirectUrl`, not `redirectURL`).
- `denyAuthorization` must NOT throw on a normal denial — server returns HTTP 200 with the OAuth error embedded in the redirect URL's query string, not an HTTP error.
- All 5 methods are session-bound (`api.authorizedExecute`, not `api.execute`).

---

## File Structure

- Modify `Sources/Auth/AuthError.swift` — add 3 `ErrorCode` static members.
- Modify `Sources/Auth/Types.swift` — add 6 new types under a new `// MARK: - OAuth Authorization Server Types` section (insert after the existing `// MARK: - OAuth Client Types` section, i.e. after `ListOAuthClientsPaginatedResponse`, before `// MARK: - JWT Claims`).
- Create `Sources/Auth/AuthOAuthServer.swift` — the new namespace struct (mirrors `Sources/Auth/AuthMFA.swift`).
- Modify `Sources/Auth/AuthClient.swift` — expose `oauthServer` computed property + `## Topics` doc entry.
- Create `Tests/AuthTests/AuthOAuthServerTests.swift` — unit tests (mirrors `Tests/AuthTests/AuthAdminOAuthTests.swift`).
- Modify `Tests/IntegrationTests/supabase/config.toml` — add `[auth.oauth_server]` block.
- Create `Tests/IntegrationTests/AuthOAuthServerIntegrationTests.swift` — integration test.

---

### Task 1: Error codes

**Files:**
- Modify: `Sources/Auth/AuthError.swift:208` (insert after the `invalidJWT` entry, still inside the `extension ErrorCode` block)
- Test: none (pure data, covered indirectly by Task 3's error-path tests)

**Interfaces:**
- Produces: `ErrorCode.oauthAuthorizationNotFound`, `ErrorCode.oauthConsentNotFound`, `ErrorCode.featureDisabled`

- [ ] **Step 1: Add the new error codes**

In `Sources/Auth/AuthError.swift`, find this line (currently the last entry in the `extension ErrorCode` block, right before its closing `}`):

```swift
  /// The provided JWT is invalid (malformed, bad signature, or expired).
  public static let invalidJWT = ErrorCode("invalid_jwt")
}
```

Replace it with:

```swift
  /// The provided JWT is invalid (malformed, bad signature, or expired).
  public static let invalidJWT = ErrorCode("invalid_jwt")
  /// No pending OAuth authorization request exists with the given ID, it has expired, or it belongs to a different user.
  public static let oauthAuthorizationNotFound = ErrorCode("oauth_authorization_not_found")
  /// No active OAuth consent/grant exists for the given client.
  public static let oauthConsentNotFound = ErrorCode("oauth_consent_not_found")
  /// The OAuth 2.1 authorization server feature is disabled for this project.
  public static let featureDisabled = ErrorCode("feature_disabled")
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build --target Auth`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Auth/AuthError.swift
git commit -m "feat(auth): add OAuth authorization server error codes"
```

---

### Task 2: New types + decode unit tests

**Files:**
- Modify: `Sources/Auth/Types.swift` (insert new section after line 1649, i.e. right after the closing `}` of `ListOAuthClientsPaginatedResponse` and before `// MARK: - JWT Claims`)
- Create: `Tests/AuthTests/AuthOAuthServerTests.swift`

**Interfaces:**
- Produces: `OAuthAuthorizationClient`, `OAuthAuthorizationUser`, `OAuthAuthorizationDetails`, `OAuthRedirect`, `OAuthAuthorizationDetailsResponse` (enum, cases `.details(OAuthAuthorizationDetails)` / `.redirect(OAuthRedirect)`), `OAuthGrant` — all `Sendable`, all (except the enum) `Codable, Hashable`.

- [ ] **Step 1: Write the failing decode tests**

Create `Tests/AuthTests/AuthOAuthServerTests.swift`:

```swift
//
//  AuthOAuthServerTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthOAuthServerTests: XCTestCase {
  let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  let userId = UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!

  var sut: AuthClient!
  var storage: InMemoryLocalStorage!

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()
  }

  override func tearDown() {
    super.tearDown()

    Mocker.removeAll()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    storage = nil
  }

  private func makeSUT() -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)

    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey": "supabase.publishable.key"
      ],
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { request in
        try await session.data(for: request)
      }
    )

    return AuthClient(configuration: configuration)
  }

  // MARK: - Decoding

  func testDecodeOAuthAuthorizationDetails() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read write"
      }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .details(let details) = response else {
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertEqual(details.authorizationId, "abc123def456")
    XCTAssertEqual(details.redirectUri, URL(string: "https://example.com/callback"))
    XCTAssertEqual(details.client.id, clientId)
    XCTAssertEqual(details.client.name, "Test Client")
    XCTAssertEqual(details.client.uri, URL(string: "https://example.com"))
    XCTAssertEqual(details.client.logoUri, URL(string: "https://example.com/logo.png"))
    XCTAssertEqual(details.user.id, userId)
    XCTAssertEqual(details.user.email, "user@example.com")
    XCTAssertEqual(details.scope, "read write")
  }

  func testDecodeOAuthAuthorizationDetailsWithMissingOptionalClientFields() throws {
    let json = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read"
      }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .details(let details) = response else {
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertNil(details.client.uri)
    XCTAssertNil(details.client.logoUri)
  }

  func testDecodeOAuthAuthorizationDetailsAutoApproveRedirect() throws {
    // The server auto-approves (and returns a bare redirect) when the user
    // already has an active consent covering the requested scopes.
    let json = """
      { "redirect_url": "https://example.com/callback?code=abc123" }
      """.data(using: .utf8)!

    let response = try AuthClient.Configuration.jsonDecoder.decode(
      OAuthAuthorizationDetailsResponse.self, from: json
    )

    guard case .redirect(let redirect) = response else {
      XCTFail("Expected .redirect case, got \(response)")
      return
    }

    XCTAssertEqual(redirect.redirectURL, URL(string: "https://example.com/callback?code=abc123"))
  }

  func testDecodeOAuthGrant() throws {
    let json = """
      {
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "scopes": ["read", "write"],
        "granted_at": "2024-01-01T00:00:00.000Z"
      }
      """.data(using: .utf8)!

    let grant = try AuthClient.Configuration.jsonDecoder.decode(OAuthGrant.self, from: json)

    XCTAssertEqual(grant.client.id, clientId)
    XCTAssertEqual(grant.scopes, ["read", "write"])
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AuthOAuthServerTests`
Expected: FAIL — `cannot find type 'OAuthAuthorizationDetailsResponse' in scope` (and similarly for the other new types).

- [ ] **Step 3: Add the new types**

In `Sources/Auth/Types.swift`, find the end of `ListOAuthClientsPaginatedResponse` (currently ends at line 1649):

```swift
  /// The total number of OAuth clients.
  public var total: Int
}

// MARK: - JWT Claims
```

Replace it with:

```swift
  /// The total number of OAuth clients.
  public var total: Int
}

// MARK: - OAuth Authorization Server Types

/// Details about the OAuth client requesting authorization.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationClient: Codable, Hashable, Sendable {
  /// Unique identifier for the OAuth client.
  public let id: UUID

  /// Human-readable name of the OAuth client.
  public let name: String

  /// URI of the OAuth client's homepage.
  public let uri: URL?

  /// URL of the OAuth client's logo.
  public let logoUri: URL?
}

/// The authenticated user considering the authorization request.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationUser: Codable, Hashable, Sendable {
  /// Unique identifier for the user.
  public let id: UUID

  /// The user's email address.
  public let email: String
}

/// Details about a pending OAuth authorization request, returned by
/// ``AuthOAuthServer/getAuthorizationDetails(authorizationId:)`` when the
/// request still requires the user's consent.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationDetails: Codable, Hashable, Sendable {
  /// Opaque identifier for this authorization request.
  public let authorizationId: String

  /// The redirect URI the client registered for this request.
  public let redirectUri: URL

  /// The OAuth client requesting authorization.
  public let client: OAuthAuthorizationClient

  /// The user considering the request.
  public let user: OAuthAuthorizationUser

  /// The requested scope.
  public let scope: String
}

/// A redirect URL returned after approving or denying an OAuth authorization
/// request, or in place of ``OAuthAuthorizationDetails`` when the server
/// auto-approves a request the user has already consented to.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthRedirect: Codable, Hashable, Sendable {
  /// The URL the client app should be redirected to. On denial, this URL's
  /// query string carries an `error=access_denied` parameter (RFC 6749) —
  /// denial is a successful API call, not a thrown error.
  public let redirectURL: URL

  private enum CodingKeys: String, CodingKey {
    case redirectURL = "redirect_url"
  }
}

/// The response from ``AuthOAuthServer/getAuthorizationDetails(authorizationId:)``.
///
/// The server auto-approves an authorization request if the user already has
/// an active consent covering the requested scopes for that client, returning
/// ``redirect(_:)`` instead of ``details(_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public enum OAuthAuthorizationDetailsResponse: Hashable, Sendable {
  /// The authorization is pending; present these details to the user for consent.
  case details(OAuthAuthorizationDetails)

  /// The authorization was already approved automatically; redirect the user.
  case redirect(OAuthRedirect)
}

extension OAuthAuthorizationDetailsResponse: Decodable {
  public init(from decoder: Decoder) throws {
    if let details = try? OAuthAuthorizationDetails(from: decoder) {
      self = .details(details)
    } else {
      self = .redirect(try OAuthRedirect(from: decoder))
    }
  }
}

/// An OAuth grant the user has given to a third-party client app, returned by
/// ``AuthOAuthServer/listGrants()``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthGrant: Codable, Hashable, Sendable {
  /// The OAuth client the grant was given to.
  public let client: OAuthAuthorizationClient

  /// The scopes granted to the client.
  public let scopes: [String]

  /// When the grant was given.
  public let grantedAt: Date
}

// MARK: - JWT Claims
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AuthOAuthServerTests`
Expected: PASS (4 tests: `testDecodeOAuthAuthorizationDetails`, `testDecodeOAuthAuthorizationDetailsWithMissingOptionalClientFields`, `testDecodeOAuthAuthorizationDetailsAutoApproveRedirect`, `testDecodeOAuthGrant`).

- [ ] **Step 5: Format and commit**

```bash
./scripts/format.sh
git add Sources/Auth/Types.swift Tests/AuthTests/AuthOAuthServerTests.swift
git commit -m "feat(auth): add OAuth authorization server response types"
```

---

### Task 3: `AuthOAuthServer` client + `AuthClient.oauthServer` + HTTP-level tests

**Files:**
- Create: `Sources/Auth/AuthOAuthServer.swift`
- Modify: `Sources/Auth/AuthClient.swift:143-146` (Topics doc, `### Namespaces` section) and `:206-217` (add computed property after `admin`)
- Modify: `Tests/AuthTests/AuthOAuthServerTests.swift` (append HTTP-mock tests)

**Interfaces:**
- Consumes: `OAuthAuthorizationDetailsResponse`, `OAuthRedirect`, `OAuthGrant` (Task 2), `ErrorCode.oauthAuthorizationNotFound` / `.oauthConsentNotFound` (Task 1)
- Produces: `AuthOAuthServer` struct with `getAuthorizationDetails(authorizationId:)`, `approveAuthorization(authorizationId:)`, `denyAuthorization(authorizationId:)`, `listGrants()`, `revokeGrant(clientId:)`; `AuthClient.oauthServer: AuthOAuthServer`

- [ ] **Step 1: Write the failing HTTP-level tests**

Append to `Tests/AuthTests/AuthOAuthServerTests.swift` (before the final closing `}` of the class):

```swift

  // MARK: - getAuthorizationDetails

  func testGetAuthorizationDetails() async throws {
    let responseData = """
      {
        "authorization_id": "abc123def456",
        "redirect_uri": "https://example.com/callback",
        "client": {
          "id": "\(clientId)",
          "name": "Test Client",
          "uri": "https://example.com",
          "logo_uri": "https://example.com/logo.png"
        },
        "user": {
          "id": "\(userId)",
          "email": "user@example.com"
        },
        "scope": "read write"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456"),
      statusCode: 200,
      data: [.get: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456"
      """#
    }
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.oauthServer.getAuthorizationDetails(
      authorizationId: "abc123def456"
    )

    guard case .details(let details) = response else {
      XCTFail("Expected .details case, got \(response)")
      return
    }

    XCTAssertEqual(details.authorizationId, "abc123def456")
    XCTAssertEqual(details.client.name, "Test Client")
  }

  func testGetAuthorizationDetailsSessionMissing() async throws {
    sut = makeSUT()

    do {
      _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "abc123def456")
      XCTFail("Expected AuthError.sessionMissing")
    } catch AuthError.sessionMissing {
      // expected
    }
  }

  func testGetAuthorizationDetailsNotFound() async throws {
    let responseData = """
      { "error_code": "oauth_authorization_not_found", "msg": "Authorization not found" }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("oauth/authorizations/missing"),
      statusCode: 404,
      data: [.get: responseData]
    )
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    do {
      _ = try await sut.oauthServer.getAuthorizationDetails(authorizationId: "missing")
      XCTFail("Expected AuthError.api")
    } catch let AuthError.api(_, errorCode, _, _) {
      XCTAssertEqual(errorCode, .oauthAuthorizationNotFound)
    }
  }

  // MARK: - approveAuthorization / denyAuthorization

  func testApproveAuthorization() async throws {
    let responseData = """
      { "redirect_url": "https://example.com/callback?code=abc123" }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456/consent"),
      statusCode: 200,
      data: [.post: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 18" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	--data "{\"action\":\"approve\"}" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456/consent"
      """#
    }
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let redirect = try await sut.oauthServer.approveAuthorization(
      authorizationId: "abc123def456"
    )

    XCTAssertEqual(redirect.redirectURL, URL(string: "https://example.com/callback?code=abc123"))
  }

  func testDenyAuthorization() async throws {
    let responseData = """
      {
        "redirect_url": "https://example.com/callback?error=access_denied&error_description=User+denied+the+request"
      }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("oauth/authorizations/abc123def456/consent"),
      statusCode: 200,
      data: [.post: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 15" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	--data "{\"action\":\"deny\"}" \
      	"http://localhost:54321/auth/v1/oauth/authorizations/abc123def456/consent"
      """#
    }
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    // Denial must NOT throw — it's a successful API call, per RFC 6749 the
    // OAuth error is embedded in the redirect URL's query string.
    let redirect = try await sut.oauthServer.denyAuthorization(authorizationId: "abc123def456")

    XCTAssertEqual(redirect.redirectURL.query?.contains("error=access_denied"), true)
  }

  // MARK: - listGrants

  func testListGrants() async throws {
    let responseData = """
      [
        {
          "client": {
            "id": "\(clientId)",
            "name": "Test Client",
            "uri": "https://example.com",
            "logo_uri": "https://example.com/logo.png"
          },
          "scopes": ["read", "write"],
          "granted_at": "2024-01-01T00:00:00.000Z"
        }
      ]
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("user/oauth/grants"),
      statusCode: 200,
      data: [.get: responseData]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/user/oauth/grants"
      """#
    }
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let grants = try await sut.oauthServer.listGrants()

    XCTAssertEqual(grants.count, 1)
    XCTAssertEqual(grants[0].client.id, clientId)
    XCTAssertEqual(grants[0].scopes, ["read", "write"])
  }

  // MARK: - revokeGrant

  func testRevokeGrant() async throws {
    Mock(
      url: clientURL.appendingPathComponent("user/oauth/grants"),
      ignoreQuery: true,
      statusCode: 204,
      data: [.delete: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.publishable.key" \
      	"http://localhost:54321/auth/v1/user/oauth/grants?client_id=E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.oauthServer.revokeGrant(clientId: clientId)
  }

  func testRevokeGrantNotFound() async throws {
    let responseData = """
      { "error_code": "oauth_consent_not_found", "msg": "No active grant found" }
      """.data(using: .utf8)!

    Mock(
      url: clientURL.appendingPathComponent("user/oauth/grants"),
      ignoreQuery: true,
      statusCode: 404,
      data: [.delete: responseData]
    )
    .register()

    sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    do {
      try await sut.oauthServer.revokeGrant(clientId: clientId)
      XCTFail("Expected AuthError.api")
    } catch let AuthError.api(_, errorCode, _, _) {
      XCTAssertEqual(errorCode, .oauthConsentNotFound)
    }
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AuthOAuthServerTests`
Expected: FAIL — `value of type 'AuthClient' has no member 'oauthServer'`.

- [ ] **Step 3: Create `Sources/Auth/AuthOAuthServer.swift`**

```swift
//
//  AuthOAuthServer.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

public import Foundation
import HTTPTypes

/// The OAuth 2.1 authorization-server consent and grant-management API.
///
/// Lets the signed-in user approve or deny a pending OAuth authorization
/// request from a third-party app registered against this project, and view
/// or revoke grants they've already given.
///
/// Access this namespace via ``AuthClient/oauthServer``.
///
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth. Not
/// to be confused with ``AuthAdmin/oauth``, which manages OAuth *client*
/// registrations (an admin-only, secret-key operation).
///
/// ## Topics
///
/// ### Handling a pending authorization
/// - ``getAuthorizationDetails(authorizationId:)``
/// - ``approveAuthorization(authorizationId:)``
/// - ``denyAuthorization(authorizationId:)``
///
/// ### Managing grants
/// - ``listGrants()``
/// - ``revokeGrant(clientId:)``
public struct AuthOAuthServer: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].encoder }
  var decoder: JSONDecoder { Dependencies[clientID].decoder }

  /// Fetches details about a pending OAuth authorization request, to present
  /// a consent screen to the user.
  ///
  /// If the user already has an active consent covering the requested
  /// scopes for this client, the server auto-approves the request and this
  /// returns ``OAuthAuthorizationDetailsResponse/redirect(_:)`` instead of
  /// ``OAuthAuthorizationDetailsResponse/details(_:)`` — callers must handle
  /// both cases.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: Either the details to present for consent, or a redirect if already approved.
  public func getAuthorizationDetails(
    authorizationId: String
  ) async throws -> OAuthAuthorizationDetailsResponse {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("oauth/authorizations/\(authorizationId)"),
        method: .get
      )
    )
    .decoded(decoder: decoder)
  }

  /// Approves a pending OAuth authorization request.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, completing the third-party app's OAuth flow.
  public func approveAuthorization(authorizationId: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: authorizationId, action: "approve")
  }

  /// Denies a pending OAuth authorization request.
  ///
  /// This does not throw on a normal denial: the server returns a redirect
  /// URL whose query string carries an `error=access_denied` parameter
  /// (RFC 6749), which the caller should navigate the user to so the
  /// third-party app receives the OAuth error.
  ///
  /// - Parameter authorizationId: The opaque identifier of the authorization request.
  /// - Returns: The URL to redirect the user to, carrying the OAuth error.
  public func denyAuthorization(authorizationId: String) async throws -> OAuthRedirect {
    try await consent(authorizationId: authorizationId, action: "deny")
  }

  private func consent(authorizationId: String, action: String) async throws -> OAuthRedirect {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url
          .appendingPathComponent("oauth/authorizations/\(authorizationId)/consent"),
        method: .post,
        body: encoder.encode(["action": action])
      )
    )
    .decoded(decoder: decoder)
  }

  /// Lists the OAuth grants the user has given to third-party client apps.
  ///
  /// - Returns: The active grants.
  public func listGrants() async throws -> [OAuthGrant] {
    try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("user/oauth/grants"),
        method: .get
      )
    )
    .decoded(decoder: decoder)
  }

  /// Revokes a previously granted OAuth consent.
  ///
  /// This marks the consent as revoked, deletes active sessions for that
  /// OAuth client, and invalidates its associated refresh tokens.
  ///
  /// - Parameter clientId: The unique identifier of the OAuth client to revoke access for.
  public func revokeGrant(clientId: UUID) async throws {
    _ = try await api.authorizedExecute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("user/oauth/grants"),
        method: .delete,
        query: [URLQueryItem(name: "client_id", value: clientId.uuidString)]
      )
    )
  }
}
```

- [ ] **Step 4: Wire `oauthServer` into `AuthClient`**

In `Sources/Auth/AuthClient.swift`, find the `### Namespaces` doc block:

```swift
/// ### Namespaces
/// - ``mfa``
/// - ``admin``
```

Replace it with:

```swift
/// ### Namespaces
/// - ``mfa``
/// - ``admin``
/// - ``oauthServer``
```

Then find the `admin` computed property:

```swift
  /// Namespace for the GoTrue admin methods.
  /// - Warning: This methods requires `secret` key, be careful to never expose `secret`
  /// key in the client.
  nonisolated public var admin: AuthAdmin {
    AuthAdmin(clientID: clientID)
  }
```

Add immediately after it:

```swift

  /// Namespace for the OAuth 2.1 authorization server consent and grant-management API.
  nonisolated public var oauthServer: AuthOAuthServer {
    AuthOAuthServer(clientID: clientID)
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AuthOAuthServerTests`
Expected: PASS (all tests, decode + HTTP-level). If a `snapshotRequest` literal doesn't match the actual request (e.g. header ordering, `Content-Length` byte count), `InlineSnapshotTesting` fails with a diff showing the actual value — replace the literal in the test with the diff's actual output and re-run until green. This is expected/normal for snapshot tests, not a bug.

- [ ] **Step 6: Format and commit**

```bash
./scripts/format.sh
git add Sources/Auth/AuthOAuthServer.swift Sources/Auth/AuthClient.swift Tests/AuthTests/AuthOAuthServerTests.swift
git commit -m "feat(auth): add AuthClient.oauthServer namespace"
```

---

### Task 4: Integration test

**Files:**
- Modify: `Tests/IntegrationTests/supabase/config.toml`
- Create: `Tests/IntegrationTests/AuthOAuthServerIntegrationTests.swift`

**Interfaces:**
- Consumes: `AuthClientIntegrationTests.makeClient(serviceRole:)`, `signUpIfNeededOrSignIn(email:password:)`, `mockEmail()`, `mockPassword()` (existing test helpers), `admin.oauth.createClient(params:)` (existing), `oauthServer.*` (Task 3)

- [ ] **Step 1: Enable the OAuth server feature locally**

In `Tests/IntegrationTests/supabase/config.toml`, find:

```toml
[auth]
enabled = true
```

Add a new block right after the closing of the `[auth]` section's plain keys, before `[auth.rate_limit]` (i.e. after the `password_requirements = ""` line and its blank line, currently ending around line 128):

```toml
[auth.oauth_server]
enabled = true
authorization_url_path = "/oauth/consent"
allow_dynamic_registration = false

```

- [ ] **Step 2: Write the integration test**

Create `Tests/IntegrationTests/AuthOAuthServerIntegrationTests.swift`:

```swift
//
//  AuthOAuthServerIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 10/07/26.
//

import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthOAuthServerIntegrationTests: XCTestCase {
  let authClient = AuthClientIntegrationTests.makeClient()

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )
  }

  /// Performs a raw GET to `/oauth/authorize` with PKCE params, capturing the
  /// `authorization_id` from the 302 redirect's `Location` header — the
  /// endpoint that actually creates a pending `oauth_authorizations` row.
  /// `/oauth/authorize` is intentionally not part of the SDK's public
  /// surface (same as the JS port), so integration tests reach it directly.
  private func createPendingAuthorization(
    accessToken: String,
    clientId: UUID,
    redirectUri: String,
    scope: String
  ) async throws -> String {
    var components = URLComponents(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/auth/v1/oauth/authorize")!,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientId.uuidString),
      URLQueryItem(name: "redirect_uri", value: redirectUri),
      URLQueryItem(name: "scope", value: scope),
      URLQueryItem(name: "state", value: "test-state"),
      URLQueryItem(name: "code_challenge", value: String(repeating: "a", count: 43)),
      URLQueryItem(name: "code_challenge_method", value: "plain"),
    ]

    var request = URLRequest(url: components.url!)
    request.setValue(DotEnv.SUPABASE_PUBLISHABLE_KEY, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let delegate = NoRedirectSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    let (_, response) = try await session.data(for: request)

    guard
      let httpResponse = response as? HTTPURLResponse,
      let location = httpResponse.value(forHTTPHeaderField: "Location"),
      let locationComponents = URLComponents(string: location),
      let authorizationId = locationComponents.queryItems?.first(where: {
        $0.name == "authorization_id"
      })?.value
    else {
      XCTFail("Expected a redirect with an authorization_id query param, got \(response)")
      throw AuthError.sessionMissing
    }

    return authorizationId
  }

  func testApproveAuthorizationFlow() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)

    let serviceRoleClient = AuthClientIntegrationTests.makeClient(serviceRole: true)
    let redirectUri = "https://example.com/callback"
    let oauthClient = try await serviceRoleClient.admin.oauth.createClient(
      params: CreateOAuthClientParams(
        clientName: "Integration Test Client",
        redirectUris: [redirectUri]
      )
    )

    let session = try await authClient.session
    let authorizationId = try await createPendingAuthorization(
      accessToken: session.accessToken,
      clientId: oauthClient.clientId,
      redirectUri: redirectUri,
      scope: "read"
    )

    let detailsResponse = try await authClient.oauthServer.getAuthorizationDetails(
      authorizationId: authorizationId
    )

    guard case .details(let details) = detailsResponse else {
      XCTFail("Expected pending .details, got \(detailsResponse)")
      return
    }
    XCTAssertEqual(details.client.id, oauthClient.clientId)
    XCTAssertEqual(details.scope, "read")

    let approveRedirect = try await authClient.oauthServer.approveAuthorization(
      authorizationId: authorizationId
    )
    XCTAssertNotNil(approveRedirect.redirectURL)

    let grants = try await authClient.oauthServer.listGrants()
    XCTAssertTrue(grants.contains { $0.client.id == oauthClient.clientId })

    try await authClient.oauthServer.revokeGrant(clientId: oauthClient.clientId)

    let grantsAfterRevoke = try await authClient.oauthServer.listGrants()
    XCTAssertFalse(grantsAfterRevoke.contains { $0.client.id == oauthClient.clientId })

    _ = try await serviceRoleClient.admin.oauth.deleteClient(clientId: oauthClient.clientId)
  }

  func testDenyAuthorizationFlow() async throws {
    let email = mockEmail()
    let password = mockPassword()
    try await signUpIfNeededOrSignIn(email: email, password: password)

    let serviceRoleClient = AuthClientIntegrationTests.makeClient(serviceRole: true)
    let redirectUri = "https://example.com/callback"
    let oauthClient = try await serviceRoleClient.admin.oauth.createClient(
      params: CreateOAuthClientParams(
        clientName: "Integration Test Client (deny)",
        redirectUris: [redirectUri]
      )
    )

    let session = try await authClient.session
    let authorizationId = try await createPendingAuthorization(
      accessToken: session.accessToken,
      clientId: oauthClient.clientId,
      redirectUri: redirectUri,
      scope: "read"
    )

    // Denial must not throw — it's a successful call carrying an
    // access_denied error in the redirect URL.
    let denyRedirect = try await authClient.oauthServer.denyAuthorization(
      authorizationId: authorizationId
    )
    XCTAssertEqual(denyRedirect.redirectURL.query?.contains("error=access_denied"), true)

    _ = try await serviceRoleClient.admin.oauth.deleteClient(clientId: oauthClient.clientId)
  }
}

/// Suppresses automatic redirect-following so the `Location` header of a
/// 302 response can be inspected directly.
private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
```

- [ ] **Step 3: Run the integration tests locally**

```bash
cd Tests/IntegrationTests
supabase start
supabase db reset
cd ../..
INTEGRATION_TESTS=1 swift test --filter AuthOAuthServerIntegrationTests
cd Tests/IntegrationTests
supabase stop
cd ../..
```

Expected: PASS (`testApproveAuthorizationFlow`, `testDenyAuthorizationFlow`). If the local Supabase CLI's bundled `auth` version doesn't yet support `[auth.oauth_server]` in `config.toml`, `supabase start` will fail to boot or `/oauth/authorize` will 404 — in that case, note the CLI version in the task and treat this as a known infra gap rather than a code bug (the unit tests in Task 3 already give full coverage of the SDK's request/response handling independent of a live server).

- [ ] **Step 4: Commit**

```bash
git add Tests/IntegrationTests/supabase/config.toml Tests/IntegrationTests/AuthOAuthServerIntegrationTests.swift
git commit -m "test(auth): add OAuth authorization server integration tests"
```

---

### Task 5: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full unit test suite**

Run: `swift test --filter AuthTests`
Expected: PASS, no regressions in other Auth tests.

- [ ] **Step 2: Format check**

Run: `./scripts/format.sh`
Expected: no diff (already formatted in prior tasks); if it produces changes, commit them.

- [ ] **Step 3: Spell check**

Run: `npm ci --prefix tools/node && ./scripts/spell-check.sh`
Expected: PASS. If it flags new technical terms (e.g. `oauthserver`, `booleans` from doc comments), add them to `dictionary.txt` at the repo root.

- [ ] **Step 4: DocC build**

Run: `./scripts/test-docs.sh`
Expected: builds with no warnings (broken symbol links, missing docs for new public API).

- [ ] **Step 5: Full package build**

Run: `swift build`
Expected: builds with no errors or warnings across all platforms the toolchain supports locally.

- [ ] **Step 6: Final commit (if any fixups were needed)**

```bash
git add -A
git commit -m "chore(auth): fixups from verification pass"
```

(Skip this step if Steps 1-5 produced no changes.)
