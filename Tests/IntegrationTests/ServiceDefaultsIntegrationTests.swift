import Foundation
import Helpers
@_spi(Experimental) import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Checks the defaults Storage applies when the SDK leaves a field out of the request.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct ServiceDefaultsIntegrationTests {
  /// Sends a request with the secret key and no SDK in between.
  private static func raw(
    _ method: String, _ path: String, headers: [String: String] = [:], body: Data
  ) async throws -> (Data, Int) {
    var request = URLRequest(url: StorageIntegration.url.appendingPathComponent(path))
    request.httpMethod = method
    request.setValue("Bearer \(DotEnv.supabaseSecretKey)", forHTTPHeaderField: "Authorization")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  private static func expectDuplicate(_ upload: () async throws -> Void) async {
    do {
      try await upload()
      Issue.record("Expected a duplicate error")
    } catch let error as StorageError {
      #expect(error.serverError?.statusCode == 409)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func storageStoresNoCacheWithoutACacheControlHeader() async throws {
    let name = try await StorageIntegration.newBucket("cache-default")
    defer { StorageIntegration.dropBucket(name) }

    let (_, status) = try await Self.raw(
      "POST", "object/\(name)/raw.txt", headers: ["Content-Type": "text/plain"],
      body: Data("raw".utf8))
    #expect(status == 200)
    let bucket = StorageIntegration.admin.from(name)
    #expect(try await bucket.info(path: "raw.txt").cacheControl == .noCache)

    try await bucket.upload(path: "sdk.txt", data: Data("sdk".utf8))
    #expect(try await bucket.info(path: "sdk.txt").cacheControl == .maxAge(.seconds(3600)))
  }

  @Test
  func uploadWithoutUpsertDoesNotOverwrite() async throws {
    let name = try await StorageIntegration.newBucket("upsert-default")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)

    try await bucket.upload(path: "a.txt", data: Data("first".utf8))
    await Self.expectDuplicate {
      try await bucket.upload(path: "a.txt", data: Data("second".utf8))
    }
    await Self.expectDuplicate {
      try await bucket.upload(
        path: "a.txt", data: Data("second".utf8), options: UploadOptions(upsert: false))
    }
    #expect(try await bucket.download(path: "a.txt").data() == Data("first".utf8))

    try await bucket.upload(
      path: "a.txt", data: Data("third".utf8), options: UploadOptions(upsert: true))
    #expect(try await bucket.download(path: "a.txt").data() == Data("third".utf8))
  }

  @Test(.timeLimit(.minutes(3)))
  func resumableUploadWithoutUpsertDoesNotOverwrite() async throws {
    let name = try await StorageIntegration.newBucket("upsert-default-tus")
    defer { StorageIntegration.dropBucket(name) }
    var configuration = StorageClient.Configuration(
      url: StorageIntegration.url,
      headers: [.authorization: "Bearer \(DotEnv.supabaseSecretKey)"])
    configuration.resumable = ResumableUploadConfiguration(
      directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let bucket = try StorageClient(configuration: configuration).from(name)

    let first = try bucket.resumableUpload(path: "a.bin", data: Data("first".utf8))
    try await first.start()
    _ = try await first.result

    let second = try bucket.resumableUpload(path: "a.bin", data: Data("second".utf8))
    await Self.expectDuplicate {
      try await second.start()
      _ = try await second.result
    }
    #expect(try await bucket.download(path: "a.bin").data() == Data("first".utf8))
  }

  @Test
  func listWithoutOptionsReturnsTheFirst100ByNameAscending() async throws {
    let name = try await StorageIntegration.newBucket("list-default")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    let names = (0...100).map { String(format: "f%03d.txt", $0) }
    for file in names.reversed() {
      try await bucket.upload(path: "dir/\(file)", data: Data(file.utf8))
    }

    let listed = try await bucket.list(path: "dir")

    #expect(listed.map(\.name) == Array(names.prefix(100)))
  }

  @Test
  func listWithOneSortPart() async throws {
    let name = try await StorageIntegration.newBucket("list-sort-part")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    for file in ["b.txt", "c.txt", "a.txt"] {
      try await bucket.upload(path: "dir/\(file)", data: Data(file.utf8))
    }

    let byCreation = try await bucket.list(path: "dir", options: ListOptions(sortBy: .createdAt))
    #expect(byCreation.map(\.name) == ["b.txt", "c.txt", "a.txt"])

    let descending = try await bucket.list(path: "dir", options: ListOptions(order: .descending))
    #expect(descending.map(\.name) == ["c.txt", "b.txt", "a.txt"])

    let (_, status) = try await Self.raw(
      "POST", "object/list/\(name)", headers: ["Content-Type": "application/json"],
      body: Data(#"{"prefix":"dir","sortBy":{"order":"desc"}}"#.utf8))
    #expect(status == 400)
  }
}
