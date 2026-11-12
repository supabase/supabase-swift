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

@Suite
struct StorageV3ErrorTests {
  @Test
  func serverErrorIsDecodedFromTheBody() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(
      status: 400,
      response:
        #"{"statusCode":"404","error":"not_found","code":"NoSuchKey","message":"Object not found"}"#
    )

    do {
      _ = try await client.from("avatars").remove(paths: ["a.png"])
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.message == "Object not found")
      #expect(error.code == .noSuchKey)
      #expect(
        error.serverError
          == StorageError.ServerError(
            statusCode: 404, error: "not_found", message: "Object not found"))
      #expect(error.isNotFound)
    }
  }

  @Test
  func aBodyWithoutCodeStillDecodes() throws {
    let error = try JSONDecoder().decode(
      StorageError.self, from: Data(#"{"statusCode":"409","message":"Duplicate"}"#.utf8))

    #expect(error.kind == .server)
    #expect(error.code == nil)
    #expect(error.serverError?.statusCode == 409)
    #expect(error.serverError?.error == nil)
    #expect(!error.isNotFound)
  }

  @Test
  func isNotFoundReadsTheCodeAndTheBodyStatus() {
    #expect(StorageError(kind: .server, message: "", code: .noSuchBucket).isNotFound)
    #expect(
      StorageError(kind: .server, message: "", serverError: .init(statusCode: 404, message: ""))
        .isNotFound)
    #expect(!StorageError(kind: .server, message: "", code: .accessDenied).isNotFound)
    #expect(!StorageError(kind: .invalidRequest, message: "").isNotFound)
  }

  @Test
  func kindsAndCodesMatchInCatchClauses() {
    func thrown(_ error: StorageError) throws { throw error }

    do {
      try thrown(StorageError(kind: .server, message: "missing", code: .noSuchKey))
      Issue.record("Expected a StorageError")
    } catch StorageError.Code.noSuchBucket {
      Issue.record("Matched the wrong code")
    } catch StorageError.Code.noSuchKey {
    } catch {
      Issue.record("Did not match the code")
    }

    do {
      try thrown(StorageError(kind: .invalidRequest, message: "bad"))
      Issue.record("Expected a StorageError")
    } catch StorageError.Kind.server {
      Issue.record("Matched the wrong kind")
    } catch StorageError.Kind.invalidRequest {
    } catch {
      Issue.record("Did not match the kind")
    }

    #expect(!(StorageError.Kind.server ~= URLError(.badURL)))
    #expect(!(StorageError.Code.noSuchKey ~= URLError(.badURL)))
  }

  @Test
  func kindAndCodeAreOpenSets() {
    let kind: StorageError.Kind = "futureKind"
    let code: StorageError.Code = "FutureCode"

    #expect(kind.rawValue == "futureKind")
    #expect(code == StorageError.Code(rawValue: "FutureCode"))
    #expect(StorageError.Kind(rawValue: "transport") == .transport)
    #expect(StorageError.Kind.decoding.rawValue == "decoding")
    #expect(StorageError.Kind.invalidConfiguration.rawValue == "invalidConfiguration")
    #expect(StorageError.Kind.accessToken.rawValue == "accessToken")
    #expect(StorageError.Code.bucketAlreadyExists.rawValue == "BucketAlreadyExists")
  }

  @Test
  @available(*, deprecated)
  func v2FieldsKeepTheirValues() throws {
    let built = StorageError(statusCode: "404", message: "File not found", error: "NotFound")
    #expect(built.kind == .server)
    #expect(built.statusCode == "404")
    #expect(built.error == "NotFound")
    #expect(built.serverError?.statusCode == 404)
    #expect(built.serverError?.error == "NotFound")
    #expect(built.errorDescription == "File not found")

    var mutated = StorageError(message: "x")
    #expect(mutated.statusCode == nil)
    #expect(mutated.error == nil)
    mutated.statusCode = "teapot"
    mutated.error = "Odd"
    #expect(mutated.statusCode == "teapot")
    #expect(mutated.error == "Odd")
    #expect(mutated.serverError?.statusCode == nil)
    mutated.statusCode = "500"
    #expect(mutated.serverError?.statusCode == 500)

    let decoded = try JSONDecoder().decode(
      StorageError.self,
      from: Data(#"{"statusCode":"403","message":"Unauthorized access","error":"Forbidden"}"#.utf8))
    #expect(decoded.statusCode == "403")
    #expect(decoded.error == "Forbidden")
  }
}

@Suite
struct StorageV3ValueTypesTests {
  private func json(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }

  @Test
  func byteCountIsTheV2TypeWithTheV3Members() throws {
    let exact = ByteCount(bytes: 5_242_880)
    #expect(exact.rawValue == "5242880")
    #expect(exact.bytes == 5_242_880)
    #expect(try json([exact]) == "[5242880]")

    let size = ByteCount(rawValue: "1.5mb")
    #expect(size.rawValue == "1.5mb")
    #expect(size.bytes == nil)
    #expect(size == .megabytes(1.5))
    #expect(try json([size]) == #"["1.5mb"]"#)

    #expect(ByteCount(rawValue: "500") == ByteCount(bytes: 500))
    #expect(ByteCount.kilobytes(500).rawValue == "500kb")
    #expect(ByteCount.gigabytes(2).rawValue == "2gb")

    let literal: ByteCount = 1024
    #expect(literal.bytes == 1024)
    let v2: StorageByteCount = literal
    #expect(v2.rawValue == "1024")
  }

  @Test
  @available(*, deprecated)
  func byteCountV2MembersKeepTheirValues() throws {
    #expect(StorageByteCount(5).intValue == 5)
    #expect(StorageByteCount(5).stringValue == nil)
    #expect(StorageByteCount(stringValue: "5mb").stringValue == "5mb")
    #expect(StorageByteCount(stringValue: "5mb").intValue == nil)
    #expect(try json([StorageByteCount(stringValue: "123")]) == #"["123"]"#)
    #expect(StorageByteCount.megabytes(1.5).stringValue == "1.5mb")
    #expect(BucketOptions(fileSizeLimit: 5).fileSizeLimit == "5")
    #expect(BucketOptions(fileSizeLimit: .megabytes(1.5)).fileSizeLimit == "1.5mb")
  }

  @Test
  func cacheControl() throws {
    #expect(CacheControl.maxAge(.seconds(3600)).rawValue == "max-age=3600")
    #expect(CacheControl.maxAge(.milliseconds(1500)).rawValue == "max-age=1")
    #expect(CacheControl.noCache.rawValue == "no-cache")
    #expect(CacheControl.noStore.rawValue == "no-store")

    let literal: CacheControl = "max-age=60, s-maxage=3600"
    #expect(literal == CacheControl(rawValue: "max-age=60, s-maxage=3600"))

    let decoded = try JSONDecoder().decode([CacheControl].self, from: Data(#"["no-cache"]"#.utf8))
    #expect(decoded == [.noCache])
  }

  @Test
  func imageTransform() {
    var transform = ImageTransform(
      width: 200, height: 100, resize: .cover, quality: 80, format: .webp, gravity: .focalPoint,
      focalPoint: FocalPoint(x: 0.25, y: 0.75))
    #expect(transform.gravity == Gravity(rawValue: "fp"))
    #expect(transform.focalPoint?.x == 0.25)
    #expect(transform.focalPoint?.y == 0.75)
    #expect(transform.resize == .cover)
    #expect(transform.format == .webp)

    transform.gravity = "sm"
    #expect(transform.gravity == .smart)
    #expect(transform != ImageTransform())

    let all: [Gravity] = [
      .north, .south, .east, .west, .northEast, .northWest, .southEast, .southWest, .center,
      .smart, .focalPoint,
    ]
    #expect(
      all.map(\.rawValue) == [
        "no", "so", "ea", "we", "noea", "nowe", "soea", "sowe", "ce", "sm", "fp",
      ])
  }

  @Test
  func uploadedObject() {
    let id = UUID()
    let object = UploadedObject(id: id, path: "a.png", fullPath: "avatars/a.png")
    #expect(object.id == id)
    #expect(object.path == "a.png")
    #expect(object.fullPath == "avatars/a.png")
    #expect(UploadedObject(path: "a.png", fullPath: "avatars/a.png").id == nil)
    #expect(object != UploadedObject(path: "a.png", fullPath: "avatars/a.png"))
  }
}
