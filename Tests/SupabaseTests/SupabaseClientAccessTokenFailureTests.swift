import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Supabase

/// A token provider failure surfaces as the module's own error with kind `accessToken`, for the
/// facade's Auth session and for a third-party `accessToken` provider alike.
@Suite
struct SupabaseClientAccessTokenFailureTests {
  struct StorageReadError: Error {}
  struct TokenError: Error {}

  /// Throws on every read, so `auth.session()` fails with an error other than `sessionMissing`.
  struct UnreadableStorage: AuthStorage {
    func load(key: String) async throws -> Data? { throw StorageReadError() }
    func save(_ data: Data, key: String) async throws {}
    func remove(key: String) async throws {}
  }

  private let transport = RecordingTransport { _, _ in
    Issue.record("No request should be sent when the access token cannot be resolved")
    return (HTTPResponse(status: .ok), Data("[]".utf8))
  }

  private func makeClient(auth: SupabaseClient.Configuration.Auth) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: auth,
        global: SupabaseClient.Configuration.Global(http: .init(transport: transport))
      )
    )
  }

  private var sessionFailureClient: SupabaseClient {
    get throws {
      try makeClient(auth: .init(storage: UnreadableStorage(), autoRefresh: .manual))
    }
  }

  private var thirdPartyFailureClient: SupabaseClient {
    get throws {
      try makeClient(
        auth: .init(storage: InMemoryTestStorage(), accessToken: { throw TokenError() }))
    }
  }

  @Test
  func postgrestSessionFailureIsAPostgrestAccessTokenError() async throws {
    let error = await #expect(throws: PostgrestError.self) {
      try await sessionFailureClient.from("todos").select().execute()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is StorageReadError)
  }

  @Test
  func storageSessionFailureIsAStorageAccessTokenError() async throws {
    let error = await #expect(throws: StorageError.self) {
      _ = try await sessionFailureClient.storage.listBuckets()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is StorageReadError)
  }

  @Test
  func functionsSessionFailureIsAFunctionsAccessTokenError() async throws {
    let error = await #expect(throws: FunctionsError.self) {
      try await sessionFailureClient.functions.invoke("hello-world")
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is StorageReadError)
  }

  @Test
  func postgrestThirdPartyFailureIsAPostgrestAccessTokenError() async throws {
    let error = await #expect(throws: PostgrestError.self) {
      try await thirdPartyFailureClient.from("todos").select().execute()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func storageThirdPartyFailureIsAStorageAccessTokenError() async throws {
    let error = await #expect(throws: StorageError.self) {
      _ = try await thirdPartyFailureClient.storage.listBuckets()
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func functionsThirdPartyFailureIsAFunctionsAccessTokenError() async throws {
    let error = await #expect(throws: FunctionsError.self) {
      try await thirdPartyFailureClient.functions.invoke("hello-world")
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }
}
