import ConcurrencyExtras
import Foundation
import HTTPTypes
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Records every request a client sends and answers each one with a fixed response.
final class RequestRecorder: Sendable {
  let requests = LockIsolated<[URLRequest]>([])

  var last: URLRequest? { requests.value.last }

  var lastBody: String? {
    last?.httpBody.map { String(decoding: $0, as: UTF8.self) }
  }

  func header(_ name: String) -> String? {
    last?.value(forHTTPHeaderField: name)
  }

  func client(
    status: Int = 200,
    response: String = "{}",
    url: String = "http://localhost:54321/storage/v1",
    headers: [String: String] = ["apikey": "key"]
  ) -> StorageClient {
    let requests = requests
    return StorageClient(
      configuration: StorageClient.Configuration(
        url: URL(string: url)!,
        headers: headers,
        session: StorageHTTPSession(
          fetch: { request in
            requests.withValue { $0.append(request) }
            return (
              Data(response.utf8),
              HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            )
          },
          upload: { _, _ in fatalError("Storage does not use the upload closure") }
        ),
        logger: nil
      )
    )
  }
}

@Suite
struct StorageV3NamesTests {
  @Test
  func v3NamesAreTheV2Types() {
    let recorder = RequestRecorder()
    let client: StorageClient = recorder.client()
    let bucket: StorageBucket = client.from("avatars")
    let configuration: StorageClient.Configuration = client.configuration
    let v2Client: SupabaseStorageClient = client
    let v2Bucket: StorageFileApi = bucket
    let v2Configuration: StorageClientConfiguration = configuration

    #expect(v2Client === client)
    #expect(v2Bucket === bucket)
    #expect(v2Configuration.url == configuration.url)

    #expect(bucket.id == "avatars")
    #expect(configuration.usesNewHostname == false)
  }

  @Test
  func usesNewHostnameRewritesTheHost() {
    var configuration = StorageClient.Configuration(
      url: URL(string: "https://blah.supabase.co/storage/v1")!, headers: [:])
    configuration.usesNewHostname = true

    let client = StorageClient(configuration: configuration)

    #expect(client.configuration.usesNewHostname)
    #expect(
      client.configuration.url.absoluteString == "https://blah.storage.supabase.co/storage/v1")
  }

  @Test
  func settingHeaderOnClientReturnsANewClientAndReachesItsBuckets() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(response: "[]")
    let tagged = client.settingHeader(name: HTTPField.Name("X-Tag")!, value: "one")

    _ = try await tagged.listBuckets()
    #expect(recorder.header("X-Tag") == "one")
    #expect(recorder.header("apikey") == "key")

    _ = try await tagged.from("avatars").remove(paths: ["a.png"])
    #expect(recorder.header("X-Tag") == "one")

    _ = try await client.listBuckets()
    #expect(recorder.header("X-Tag") == nil)
  }

  @Test
  func settingHeaderOnBucketReturnsANewBucket() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: "[]").from("avatars")
    let tagged = bucket.settingHeader(name: HTTPField.Name("X-Tag")!, value: "one")

    #expect(tagged.id == "avatars")

    _ = try await tagged.remove(paths: ["a.png"])
    #expect(recorder.header("X-Tag") == "one")

    _ = try await bucket.remove(paths: ["a.png"])
    #expect(recorder.header("X-Tag") == nil)
  }

  @Test
  func settingHeaderReplacesAHeaderWhateverItsCase() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(response: "[]", headers: ["Authorization": "Bearer old"])
      .settingHeader(name: .authorization, value: "Bearer new")

    _ = try await client.listBuckets()

    #expect(recorder.header("Authorization") == "Bearer new")
  }

  @Test
  @available(*, deprecated)
  func deprecatedSpellingsKeepWorking() async throws {
    let recorder = RequestRecorder()
    let configuration = StorageClientConfiguration(
      url: URL(string: "http://localhost:54321/storage/v1")!, headers: [:], useNewHostname: true)
    #expect(configuration.useNewHostname)

    let mutated = recorder.client(response: "[]").from("avatars")
    #expect(mutated.setHeader("one", forKey: "X-Tag") === mutated)
    _ = try await mutated.remove(paths: ["a.png"])
    #expect(recorder.header("X-Tag") == "one")

    let copy = mutated.settingHeader(name: HTTPField.Name("X-Other")!, value: "two")
    _ = try await copy.remove(paths: ["a.png"])
    #expect(recorder.header("X-Tag") == "one")
    #expect(recorder.header("X-Other") == "two")
  }
}
