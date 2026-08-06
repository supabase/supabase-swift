import ConcurrencyExtras
import Foundation
import SnapshotTesting
import TestHelpers
import Testing

@testable import Auth

#if os(Android)
  private let isAndroid = true
#else
  private let isAndroid = false
#endif

@Suite
struct StoredSessionTests {
  @Test
  func get_withCorruptedJSON_returnsNil() throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(
      key: "supabase.auth.token",
      value: Data("not-valid-json".utf8)
    )

    let dependencies = DependenciesContainer()
    dependencies.bootstrap(
      Dependencies(
        configuration: AuthClient.Configuration(
          url: URL(string: "http://localhost")!,
          storageKey: "supabase.auth.token",
          localStorage: localStorage,
          logger: nil
        ),
        http: HTTPClientMock(),
        api: .init(dependencies: dependencies),
        codeVerifierStorage: .mock,
        sessionStorage: .live(dependencies: dependencies),
        sessionManager: .live(dependencies: dependencies)
      )
    )

    let sut = dependencies.value.sessionStorage
    #expect(sut.get() == nil)
  }

  @Test(
    .disabled(
      if: isAndroid, "Disabled for android due to #filePath not existing on emulator"
    )
  )
  func storedSession() throws {
    let dependencies = DependenciesContainer()
    dependencies.bootstrap(
      Dependencies(
        configuration: AuthClient.Configuration(
          url: URL(string: "http://localhost")!,
          storageKey: "supabase.auth.token",
          localStorage: try! DiskTestStorage(),
          logger: nil
        ),
        http: HTTPClientMock(),
        api: .init(dependencies: dependencies),
        codeVerifierStorage: .mock,
        sessionStorage: .live(dependencies: dependencies),
        sessionManager: .live(dependencies: dependencies)
      )
    )

    let sut = dependencies.value.sessionStorage

    #expect(sut.get() != nil)

    let session = Session(
      accessToken: "accesstoken",
      tokenType: "bearer",
      expiresIn: 120,
      expiresAt: ISO8601DateFormatter().date(from: "2024-04-01T13:25:07Z")!.timeIntervalSince1970,
      refreshToken: "refreshtoken",
      user: User(
        id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
        appMetadata: [
          "provider": "email",
          "providers": [
            "email"
          ],
        ],
        userMetadata: [
          "referrer_id": nil
        ],
        aud: "authenticated",
        confirmationSentAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!,
        recoverySentAt: nil,
        emailChangeSentAt: nil,
        newEmail: nil,
        invitedAt: nil,
        actionLink: nil,
        email: "johndoe@supabsae.com",
        phone: "",
        createdAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!,
        confirmedAt: nil,
        emailConfirmedAt: nil,
        phoneConfirmedAt: nil,
        lastSignInAt: nil,
        role: "authenticated",
        updatedAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!,
        identities: [
          UserIdentity(
            id: "859f402d-b3de-4105-a1b9-932836d9193b",
            identityId: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
            userId: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
            identityData: [
              "sub": "859f402d-b3de-4105-a1b9-932836d9193b"
            ],
            provider: "email",
            createdAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!,
            lastSignInAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!,
            updatedAt: ISO8601DateFormatter().date(from: "2022-04-09T11:57:01Z")!
          )
        ],
        factors: nil
      )
    )

    sut.store(session)
    #expect(sut.get() != nil)
  }

  private final class DiskTestStorage: AuthLocalStorage {
    let url: URL
    let storage: LockIsolated<[String: AnyJSON]>

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init() throws {
      url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("local-storage.json")

      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

      if !FileManager.default.fileExists(atPath: url.path) {
        let contents = "{}".data(using: .utf8)
        FileManager.default.createFile(atPath: url.path, contents: contents)
      }

      let contents = try Data(contentsOf: url)
      storage = try LockIsolated(decoder.decode([String: AnyJSON].self, from: contents))
    }

    func store(key: String, value: Data) throws {
      let json = try decoder.decode(AnyJSON.self, from: value)
      storage.withValue {
        $0[key] = json
      }

      try saveToDisk()
    }

    func retrieve(key: String) throws -> Data? {
      guard let json = storage[key] else { return nil }
      return try encoder.encode(json)
    }

    func remove(key: String) throws {
      storage.withValue {
        $0[key] = nil
      }
      try saveToDisk()
    }

    private func saveToDisk() throws {
      let data = try encoder.encode(storage.value)
      try data.write(to: url)
    }
  }
}
