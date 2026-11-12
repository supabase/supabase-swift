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

  /// The last request body as JSON. Key order is not compared: other suites change the output
  /// formatting of the shared default encoder.
  var lastJSON: [String: AnyJSON]? {
    last?.httpBody.flatMap { try? JSONDecoder().decode([String: AnyJSON].self, from: $0) }
  }

  var lastURL: String? { last?.url?.absoluteString }

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
      url: URL(string: "https://blah.supabase.co/storage/v1")!, headers: [:], logger: nil)
    configuration.usesNewHostname = true

    let client = StorageClient(configuration: configuration)

    #expect(client.configuration.usesNewHostname)
    #expect(
      client.configuration.url.absoluteString == "https://blah.storage.supabase.co/storage/v1")
  }

  @Test
  func theV3ShapedConfigurationInitTakesHTTPFields() {
    let url = URL(string: "https://blah.supabase.co/storage/v1")!

    let plain = StorageClient.Configuration(url: url)
    #expect(plain.headers.isEmpty)
    #expect(!plain.usesNewHostname)
    #expect(plain.logger == nil)

    var fields = HTTPFields()
    fields[.authorization] = "Bearer token"
    fields.append(HTTPField(name: .accept, value: "a/b"))
    fields.append(HTTPField(name: .accept, value: "c/d"))
    let configured = StorageClient.Configuration(url: url, headers: fields, usesNewHostname: true)
    #expect(configured.headers == ["Authorization": "Bearer token", "Accept": "a/b, c/d"])
    #expect(configured.usesNewHostname)

    let literal = StorageClient.Configuration(url: url, headers: [.authorization: "Bearer token"])
    #expect(literal.headers == ["Authorization": "Bearer token"])
  }

  /// The v2 spellings of the configuration init keep their overload.
  @Test
  @available(*, deprecated)
  func v2ConfigurationCallSitesKeepTheV2Init() {
    let url = URL(string: "https://blah.supabase.co/storage/v1")!

    let empty = StorageClientConfiguration(url: url, headers: [:])
    #expect(empty.headers == [:])
    let literal = StorageClientConfiguration(url: url, headers: ["apikey": "key"])
    #expect(literal.headers == ["apikey": "key"])
    let labelled = StorageClientConfiguration(
      url: url, headers: ["apikey": "key"], logger: nil, useNewHostname: true)
    #expect(labelled.useNewHostname)
    let headers = ["apikey": "key"]
    #expect(StorageClientConfiguration(url: url, headers: headers).headers == headers)
  }

  @Test
  func settingHeaderIsOnTheBaseClasses() async throws {
    let recorder = RequestRecorder()
    let buckets: StorageBucketApi = recorder.client(response: "[]")
    let tagged: StorageBucketApi = buckets.settingHeader(
      name: HTTPField.Name("X-Tag")!, value: "one")

    _ = try await tagged.listBuckets()
    #expect(recorder.header("X-Tag") == "one")
    _ = try await buckets.listBuckets()
    #expect(recorder.header("X-Tag") == nil)

    let api = StorageApi(
      configuration: StorageClient.Configuration(url: URL(string: "http://localhost:54321")!))
    let taggedAPI: StorageApi = api.settingHeader(name: HTTPField.Name("X-Tag")!, value: "two")
    #expect(taggedAPI.configuration.headers["X-Tag"] == "two")
    #expect(api.configuration.headers["X-Tag"] == nil)

    let client: StorageClient = recorder.client()
    let sameClient: StorageClient = client.settingHeader(name: .accept, value: "a/b")
    let sameBucket: StorageBucket = client.from("avatars").settingHeader(
      name: .accept, value: "a/b")
    #expect(sameClient.configuration.headers["Accept"] == "a/b")
    #expect(sameBucket.id == "avatars")
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

/// `true` when the overload the compiler chose returns `Void`, as the v2 bucket methods do.
private func returnsVoid<T>(_ value: T) -> Bool {
  T.self == Void.self
}

@Suite
struct StorageV3BucketTests {
  let bucketJSON = """
    {
      "id": "avatars",
      "name": "avatars",
      "owner": "owner123",
      "public": true,
      "type": "STANDARD",
      "versioning_status": "ENABLED",
      "file_size_limit": 1000,
      "allowed_mime_types": ["image/png"],
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-02T00:00:00.000Z"
    }
    """

  @Test
  func bucketDecodesTheV3Fields() async throws {
    let recorder = RequestRecorder()
    let bucket = try await recorder.client(response: bucketJSON).bucket("avatars")

    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket/avatars")
    #expect(recorder.last?.httpMethod == "GET")
    #expect(bucket.id == "avatars")
    #expect(bucket.ownerID == "owner123")
    #expect(bucket.type == .standard)
    #expect(bucket.versioningStatus == .enabled)
    #expect(bucket.isPublic)
    #expect(bucket.fileSizeLimit == 1000)
  }

  @Test
  func bucketWithoutTheNewFieldsStillDecodes() throws {
    let json = """
      {
        "id": "avatars", "name": "avatars", "owner": "", "public": false,
        "created_at": "2024-01-01T00:00:00.000Z", "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """
    let bucket = try JSONDecoder.supabase().decode(Bucket.self, from: Data(json.utf8))

    #expect(bucket.type == nil)
    #expect(bucket.versioningStatus == nil)
    #expect(bucket.ownerID == nil)
  }

  @Test
  func bucketInitializerTakesTheV3Labels() throws {
    let date = Date(timeIntervalSince1970: 0)
    var bucket = Bucket(
      id: "a", name: "a", type: .analytics, ownerID: "me", isPublic: false, createdAt: date,
      updatedAt: date, versioningStatus: .suspended)
    #expect(bucket.ownerID == "me")
    #expect(bucket.type == BucketType(rawValue: "ANALYTICS"))
    #expect(bucket.versioningStatus == "SUSPENDED")

    bucket.ownerID = nil
    #expect(bucket.ownerID == nil)
    #expect(
      Bucket(id: "a", name: "a", isPublic: false, createdAt: date, updatedAt: date).ownerID == nil)

    let encoded = try JSONDecoder().decode(
      [String: AnyJSON].self, from: JSONEncoder().encode(bucket))
    #expect(encoded["owner"] == "")
    #expect(encoded["type"] == "ANALYTICS")
    #expect(encoded["versioning_status"] == "SUSPENDED")
  }

  @Test
  @available(*, deprecated)
  func bucketV2MembersKeepTheirValues() throws {
    let date = Date(timeIntervalSince1970: 0)
    var bucket = Bucket(
      id: "a", name: "a", owner: "me", isPublic: false, createdAt: date, updatedAt: date)
    #expect(bucket.owner == "me")
    #expect(bucket.ownerID == "me")
    bucket.owner = "you"
    #expect(bucket.ownerID == "you")

    let encoded = try JSONDecoder().decode(
      [String: AnyJSON].self, from: JSONEncoder().encode(bucket))
    #expect(Set(encoded.keys) == ["id", "name", "owner", "public", "created_at", "updated_at"])
  }

  @Test
  @available(*, deprecated)
  func getBucketKeepsWorking() async throws {
    let recorder = RequestRecorder()
    let bucket = try await recorder.client(response: bucketJSON).getBucket("avatars")
    #expect(bucket.owner == "owner123")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket/avatars")
  }

  @Test
  func listBucketsSendsTheOptionsAsQuery() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(response: "[\(bucketJSON)]")

    let buckets = try await client.listBuckets(
      options: BucketListOptions(
        limit: 10, offset: 20, sortBy: .createdAt, order: .descending, search: "ava"))
    #expect(buckets.map(\.id) == ["avatars"])
    #expect(
      recorder.lastURL
        == "http://localhost:54321/storage/v1/bucket?limit=10&offset=20&sortColumn=created_at&sortOrder=desc&search=ava"
    )

    _ = try await client.listBuckets(options: BucketListOptions())
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket")

    _ = try await client.listBuckets()
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket")

    let columns: [BucketSortColumn] = [.id, .name, .createdAt, .updatedAt]
    #expect(columns.map(\.rawValue) == ["id", "name", "created_at", "updated_at"])
  }

  @Test
  func createBucketWithCreateBucketOptionsSendsOnlyTheSetFields() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(response: #"{"name":"stored"}"#)

    let name = try await client.createBucket("avatars", options: CreateBucketOptions())
    #expect(name == "stored")
    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket")
    #expect(recorder.lastJSON == ["id": "avatars", "name": "avatars"])

    try await client.createBucket(
      "avatars",
      options: CreateBucketOptions(
        isPublic: true, fileSizeLimit: .megabytes(5), allowedMimeTypes: ["image/png"],
        type: .standard, versioningStatus: .enabled))
    #expect(
      recorder.lastJSON == [
        "id": "avatars", "name": "avatars", "public": true, "file_size_limit": "5mb",
        "allowed_mime_types": ["image/png"], "type": "STANDARD", "versioning_status": "ENABLED",
      ])

    let annotated: String = try await client.createBucket("avatars")
    #expect(annotated == "stored")
    #expect(recorder.lastJSON == ["id": "avatars", "name": "avatars"])
  }

  @Test
  func updateBucketWithUpdateBucketOptionsSendsOnlyTheSetFields() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client()

    try await client.updateBucket(
      "avatars", options: UpdateBucketOptions(allowedMimeTypes: ["image/png"]))
    #expect(recorder.last?.httpMethod == "PUT")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/bucket/avatars")
    #expect(recorder.lastJSON == ["allowed_mime_types": ["image/png"]])

    try await client.updateBucket(
      "avatars",
      options: UpdateBucketOptions(
        isPublic: false, fileSizeLimit: 1024, versioningStatus: .suspended))
    #expect(
      recorder.lastJSON == [
        "public": false, "file_size_limit": 1024, "versioning_status": "SUSPENDED",
      ])
  }

  @Test
  func updateBucketWithNoFieldThrowsBeforeSending() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client()

    do {
      try await client.updateBucket("avatars", options: UpdateBucketOptions())
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .invalidRequest)
    }
    #expect(recorder.requests.value.isEmpty)
  }

  /// A v2 call site, with the v2 labels and no type annotation, keeps the v2 overload: it
  /// returns `Void` and always sends `public`.
  @Test
  @available(*, deprecated)
  func v2CallSitesKeepTheV2Overload() async throws {
    let recorder = RequestRecorder()
    let client = recorder.client(response: #"{"name":"stored"}"#)

    #expect(returnsVoid(try await client.createBucket("avatars")))
    #expect(recorder.lastJSON == ["id": "avatars", "name": "avatars", "public": false])

    #expect(returnsVoid(try await client.createBucket("avatars", options: .init(isPublic: true))))
    #expect(recorder.lastJSON == ["id": "avatars", "name": "avatars", "public": true])

    try await client.createBucket("avatars", options: .init(fileSizeLimit: .megabytes(1)))
    #expect(
      recorder.lastJSON == [
        "id": "avatars", "name": "avatars", "public": false, "file_size_limit": "1mb",
      ])

    try await client.updateBucket("avatars", options: .init(allowedMimeTypes: ["image/png"]))
    #expect(
      recorder.lastJSON == [
        "id": "avatars", "name": "avatars", "public": false,
        "allowed_mime_types": ["image/png"],
      ])

    try await client.updateBucket("avatars", options: .init(isPublic: true))
    #expect(recorder.lastJSON == ["id": "avatars", "name": "avatars", "public": true])

    let task = Task { try await client.createBucket("avatars") }
    let _: Void = try await task.value
  }
}

@Suite
struct StorageV3UploadTests {
  let uploadResponse =
    #"{"Key":"avatars/folder/a.png","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}"#
  let base = "http://localhost:54321/storage/v1"

  private func field(_ name: String, in body: String?) -> String? {
    guard let body, let start = body.range(of: "name=\"\(name)\"\r\n\r\n") else { return nil }
    let rest = body[start.upperBound...]
    return rest.range(of: "\r\n").map { String(rest[..<$0.lowerBound]) }
  }

  @Test
  func uploadSendsTheV2MultipartFormAndReturnsAnUploadedObject() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")

    let object = try await bucket.upload(path: "/folder//a.png", data: Data("hello".utf8))

    #expect(object.id == UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
    #expect(object.path == "folder/a.png")
    #expect(object.fullPath == "avatars/folder/a.png")
    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "\(base)/object/avatars/folder/a.png")
    #expect(recorder.header("x-upsert") == "false")
    #expect(recorder.header("Cache-Control") == "max-age=3600")
    #expect(recorder.header("Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    #expect(field("cacheControl", in: recorder.lastBody) == "3600")
    #expect(recorder.lastBody?.contains("name=\"metadata\"") == false)
    #expect(recorder.lastBody?.contains("filename=\"a.png\"\r\nContent-Type: image/png") == true)
    #expect(recorder.lastBody?.contains("hello") == true)
  }

  @Test
  func uploadSendsEveryOption() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")

    try await bucket.upload(
      path: "folder/a.bin", data: Data("hello".utf8),
      options: UploadOptions(
        contentType: "image/webp", cacheControl: .maxAge(.seconds(60)), upsert: true,
        metadata: ["kind": "avatar"], headers: [HTTPField.Name("X-Extra")!: "1"]))

    #expect(recorder.header("x-upsert") == "true")
    #expect(recorder.header("Cache-Control") == "max-age=60")
    #expect(recorder.header("X-Extra") == "1")
    #expect(field("cacheControl", in: recorder.lastBody) == "60")
    #expect(field("metadata", in: recorder.lastBody) == #"{"kind":"avatar"}"#)
    #expect(recorder.lastBody?.contains("Content-Type: image/webp") == true)
  }

  @Test
  func cacheControlMapsToTheMultipartFieldOnlyWhenTheMappingIsExact() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")
    let data = Data("hello".utf8)

    try await bucket.upload(
      path: "a.png", data: data, options: UploadOptions(cacheControl: .noCache))
    #expect(recorder.lastBody?.contains("name=\"cacheControl\"") == false)
    #expect(recorder.header("Cache-Control") == "no-cache")

    try await bucket.upload(
      path: "a.png", data: data,
      options: UploadOptions(cacheControl: "max-age=60, s-maxage=3600"))
    #expect(field("cacheControl", in: recorder.lastBody) == "60, s-maxage=3600")
    #expect(recorder.header("Cache-Control") == "max-age=60, s-maxage=3600")

    let sent = recorder.requests.value.count
    for unsupported: CacheControl in [.noStore, "public", "max-age="] {
      do {
        try await bucket.upload(
          path: "a.png", data: data, options: UploadOptions(cacheControl: unsupported))
        Issue.record("Expected a StorageError for \(unsupported.rawValue)")
      } catch let error as StorageError {
        #expect(error.kind == .invalidRequest)
      }
    }
    #expect(recorder.requests.value.count == sent)
  }

  @Test
  func updateSendsPutWithoutUpsert() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")

    let object = try await bucket.update(
      path: "folder/a.png", data: Data("hello".utf8), options: UploadOptions(upsert: true))

    #expect(object.fullPath == "avatars/folder/a.png")
    #expect(recorder.last?.httpMethod == "PUT")
    #expect(recorder.lastURL == "\(base)/object/avatars/folder/a.png")
    #expect(recorder.header("x-upsert") == nil)
  }

  @Test
  func fileURLUploadsTakeTheContentTypeFromTheFile() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("storage-v3-\(UUID().uuidString).txt")
    try Data("from disk".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let uploaded = try await bucket.upload(path: "folder/a", fileURL: fileURL)
    #expect(uploaded.path == "folder/a")
    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastBody?.contains("Content-Type: text/plain") == true)
    #expect(recorder.lastBody?.contains("from disk") == true)

    try await bucket.update(path: "folder/a", fileURL: fileURL)
    #expect(recorder.last?.httpMethod == "PUT")
    #expect(recorder.lastBody?.contains("from disk") == true)

    let signed = try await bucket.uploadToSignedURL(
      path: "folder/a", token: "tok", fileURL: fileURL)
    #expect(signed.id == nil)
    #expect(recorder.lastURL == "\(base)/object/upload/sign/avatars/folder/a?token=tok")
    #expect(recorder.lastBody?.contains("from disk") == true)
  }

  @Test
  func uploadToSignedURL() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/a.png"}"#).from("avatars")

    let object = try await bucket.uploadToSignedURL(
      path: "a.png", token: "tok", data: Data("hello".utf8),
      options: UploadOptions(cacheControl: .maxAge(.seconds(10))))

    #expect(object == UploadedObject(id: nil, path: "a.png", fullPath: "avatars/a.png"))
    #expect(recorder.last?.httpMethod == "PUT")
    #expect(recorder.lastURL == "\(base)/object/upload/sign/avatars/a.png?token=tok")
    #expect(field("cacheControl", in: recorder.lastBody) == "10")
  }

  /// A v2 call site keeps the v2 overload, its result type and its request.
  @Test
  @available(*, deprecated)
  func v2CallSitesKeepTheV2Overload() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: uploadResponse).from("avatars")
    let data = Data("hello".utf8)

    let uploaded = try await bucket.upload("folder/a.png", data: data)
    #expect(type(of: uploaded) == FileUploadResponse.self)
    #expect(uploaded.id.count == 36)
    #expect(field("cacheControl", in: recorder.lastBody) == "3600")
    #expect(recorder.header("Cache-Control") == "max-age=3600")
    #expect(recorder.header("x-upsert") == "false")

    let withOptions = try await bucket.upload(
      "folder/a.png", data: data, options: .init(cacheControl: "60", upsert: true))
    #expect(type(of: withOptions) == FileUploadResponse.self)
    #expect(field("cacheControl", in: recorder.lastBody) == "60")
    #expect(recorder.header("x-upsert") == "true")

    let updated = try await bucket.update("folder/a.png", data: data)
    #expect(type(of: updated) == FileUploadResponse.self)
    #expect(recorder.last?.httpMethod == "PUT")

    let signed = try await bucket.uploadToSignedURL("folder/a.png", token: "tok", data: data)
    #expect(type(of: signed) == SignedURLUploadResponse.self)
    #expect(recorder.header("x-upsert") == "false")
    #expect(field("cacheControl", in: recorder.lastBody) == "3600")

    let legacy: FileUploadResponse = try await bucket.upload(path: "folder/a.png", file: data)
    #expect(legacy.fullPath == "avatars/folder/a.png")
  }
}

@Suite
struct StorageV3URLTests {
  let base = "http://localhost:54321/storage/v1"
  let signResponse = #"{"signedURL":"/object/sign/avatars/a.png?token=abc"}"#

  @Test
  func createSignedURLTakesADuration() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: signResponse).from("avatars")

    let url = try await bucket.createSignedURL(path: "a.png", expiresIn: .seconds(60))

    #expect(url.absoluteString == "\(base)/object/sign/avatars/a.png?token=abc")
    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "\(base)/object/sign/avatars/a.png")
    #expect(recorder.lastJSON == ["expiresIn": 60])

    _ = try await bucket.createSignedURL(path: "a.png", expiresIn: .milliseconds(90_500))
    #expect(recorder.lastJSON == ["expiresIn": 90])
  }

  @Test
  func createSignedURLSendsTheOptions() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: signResponse).from("avatars")

    let url = try await bucket.createSignedURL(
      path: "a.png", expiresIn: .seconds(60),
      options: SignedURLOptions(
        download: .named("x.png"),
        transform: ImageTransform(
          width: 100, resize: .cover, gravity: .focalPoint,
          focalPoint: FocalPoint(x: 0.25, y: 0.75)),
        versionID: "v1", cacheNonce: "n1"))

    #expect(
      url.absoluteString
        == "\(base)/object/sign/avatars/a.png?token=abc&download=x.png&cacheNonce=n1")
    #expect(
      recorder.lastJSON == [
        "expiresIn": 60,
        "transform": [
          "width": 100, "resize": "cover", "gravity": "fp", "x_offset": 0.25, "y_offset": 0.75,
        ],
        "versionId": "v1",
      ])

    _ = try await bucket.createSignedURL(
      path: "a.png", expiresIn: .seconds(60),
      options: SignedURLOptions(download: .withOriginalName, transform: ImageTransform()))
    #expect(recorder.lastJSON == ["expiresIn": 60])
  }

  @Test
  func anExpiryUnderOneSecondThrowsBeforeSending() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: signResponse).from("avatars")

    do {
      _ = try await bucket.createSignedURL(path: "a.png", expiresIn: .milliseconds(999))
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .invalidRequest)
    }
    do {
      _ = try await bucket.createSignedURLs(paths: ["a.png"], expiresIn: .zero)
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .invalidRequest)
    }
    #expect(recorder.requests.value.isEmpty)
  }

  @Test
  func createSignedURLsTakesADurationAndOptions() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(
      response: """
        [
          {"signedURL":"/object/sign/avatars/a.png?token=abc","path":"a.png","error":null},
          {"signedURL":null,"path":"missing.png","error":"Either the object does not exist or you do not have access to it"}
        ]
        """
    ).from("avatars")

    let results = try await bucket.createSignedURLs(
      paths: ["a.png", "missing.png"], expiresIn: .seconds(3600),
      options: SignedURLsOptions(download: .withOriginalName, cacheNonce: "n1"))

    #expect(recorder.lastURL == "\(base)/object/sign/avatars")
    #expect(recorder.lastJSON == ["expiresIn": 3600, "paths": ["a.png", "missing.png"]])
    #expect(results.count == 2)
    #expect(
      results[0].signedURL?.absoluteString
        == "\(base)/object/sign/avatars/a.png?token=abc&download=&cacheNonce=n1")
    #expect(results[1].path == "missing.png")
    #expect(results[1].signedURL == nil)
    #expect(results[1].error != nil)

    let plain = try await bucket.createSignedURLs(paths: ["a.png"], expiresIn: .seconds(1))
    #expect(recorder.lastJSON == ["expiresIn": 1, "paths": ["a.png"]])
    #expect(plain.first?.signedURL?.absoluteString == "\(base)/object/sign/avatars/a.png?token=abc")
  }

  @Test
  func publicURL() {
    let bucket = RequestRecorder().client().from("avatars")

    #expect(
      bucket.publicURL(path: "folder/a.png").absoluteString
        == "\(base)/object/public/avatars/folder/a.png")
    #expect(
      bucket.publicURL(
        path: "/a.png",
        options: PublicURLOptions(download: .named("x.png"), versionID: "v1", cacheNonce: "n1")
      ).absoluteString
        == "\(base)/object/public/avatars/a.png?download=x.png&cacheNonce=n1&versionId=v1")
    #expect(
      bucket.publicURL(
        path: "a.png",
        options: PublicURLOptions(
          transform: ImageTransform(width: 200, format: .webp, gravity: .smart))
      ).absoluteString
        == "\(base)/render/image/public/avatars/a.png?width=200&format=webp&gravity=sm")
    #expect(
      bucket.publicURL(path: "a.png", options: PublicURLOptions(transform: ImageTransform()))
        .absoluteString == "\(base)/object/public/avatars/a.png")
  }

  @Test
  func createSignedUploadURLTakesUpsert() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(
      response: #"{"url":"/object/upload/sign/avatars/a.png?token=tok"}"#
    ).from("avatars")

    let plain = try await bucket.createSignedUploadURL(path: "/a.png")
    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "\(base)/object/upload/sign/avatars/a.png")
    #expect(recorder.header("x-upsert") == nil)
    #expect(plain.token == "tok")
    #expect(plain.path == "a.png")
    #expect(plain.signedURL.absoluteString == "\(base)/object/upload/sign/avatars/a.png?token=tok")

    _ = try await bucket.createSignedUploadURL(path: "a.png", upsert: true)
    #expect(recorder.header("x-upsert") == "true")

    var built = SignedUploadURL(signedURL: plain.signedURL, path: "a.png", token: "one")
    built.token = "two"
    #expect(built.token == "two")
  }

  @Test
  func aSignedUploadURLWithoutATokenThrowsADecodingKind() async throws {
    let bucket = RequestRecorder().client(response: #"{"url":"/object/upload/sign/avatars/a.png"}"#)
      .from("avatars")

    do {
      _ = try await bucket.createSignedUploadURL(path: "a.png")
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .decoding)
      #expect(error.message == "No token returned by API")
    }
  }

  /// The v2 spellings keep their overloads, results and requests.
  @Test
  @available(*, deprecated)
  func v2CallSitesKeepTheV2Overload() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: signResponse).from("avatars")

    let url = try await bucket.createSignedURL(path: "a.png", expiresIn: 60)
    #expect(url.absoluteString == "\(base)/object/sign/avatars/a.png?token=abc")
    #expect(recorder.lastJSON == ["expiresIn": 60])

    let transformed = try await bucket.createSignedURL(
      path: "a.png", expiresIn: 60, download: .withOriginalName,
      transform: TransformOptions(width: 100, resize: .cover), cacheNonce: "n1")
    #expect(
      transformed.absoluteString
        == "\(base)/object/sign/avatars/a.png?token=abc&download=&cacheNonce=n1")
    #expect(
      recorder.lastJSON == ["expiresIn": 60, "transform": ["width": 100, "resize": "cover"]])

    _ = try await bucket.createSignedURL(
      path: "a.png", expiresIn: 60, transform: TransformOptions())
    #expect(recorder.lastJSON == ["expiresIn": 60, "transform": [:]])

    #expect(
      try bucket.getPublicURL(path: "a.png", download: .named("x.png"), cacheNonce: "n1")
        == bucket.publicURL(
          path: "a.png", options: PublicURLOptions(download: .named("x.png"), cacheNonce: "n1")))
    #expect(
      try bucket.getPublicURL(path: "a.png", options: TransformOptions(width: 200)).absoluteString
        == "\(base)/render/image/public/avatars/a.png?width=200")

    let upload = recorder.client(
      response: #"{"url":"/object/upload/sign/avatars/a.png?token=tok"}"#
    ).from("avatars")
    let signed = try await upload.createSignedUploadURL(
      path: "a.png", options: CreateSignedUploadURLOptions(upsert: true))
    #expect(signed.token == "tok")
    #expect(recorder.header("x-upsert") == "true")
    _ = try await upload.createSignedUploadURL(path: "a.png", options: nil)
    #expect(recorder.header("x-upsert") == nil)
  }
}

@Suite
struct StorageV3ObjectTests {
  let objectID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

  var listResponse: String {
    """
    [
      {"name":"folder","id":null,"updated_at":null,"created_at":null,"last_accessed_at":null,
       "metadata":null},
      {"name":"a.png","id":"\(objectID)","version":"v1",
       "updated_at":"2024-01-02T03:04:05.000Z","created_at":"2024-01-01T00:00:00.000Z",
       "last_accessed_at":"2024-01-03T00:00:00.000Z",
       "metadata":{"eTag":"\\"abc\\"","size":42,"mimetype":"image/png",
                   "cacheControl":"max-age=3600","lastModified":"2024-01-02T03:04:05.000Z",
                   "contentLength":42,"httpStatusCode":200},
       "user_metadata":{"owner":"me"},"is_versioned":true,"is_delete_marker":false}
    ]
    """
  }

  var infoResponse: String {
    """
    {"id":"\(objectID)","version":"v1","name":"a.png","bucket_id":"avatars","size":42,
     "content_type":"image/png","cache_control":"no-cache","etag":"\\"abc\\"",
     "last_modified":"2024-01-02T03:04:05.000Z","created_at":"2024-01-01T00:00:00.000Z",
     "metadata":{"owner":"me"},"is_versioned":true}
    """
  }

  @Test
  func listWithListOptionsSendsTheDefaultsAndDecodesStorageObjects() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: listResponse).from("avatars")

    let objects = try await bucket.list(path: "users", options: ListOptions())

    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/list/avatars")
    #expect(
      recorder.lastJSON == [
        "prefix": "users", "limit": 100, "offset": 0,
        "sortBy": ["column": "name", "order": "asc"],
      ])

    #expect(objects.count == 2)
    #expect(objects[0].name == "folder")
    #expect(objects[0].isFolder)
    #expect(objects[0].metadata == nil)

    let file = objects[1]
    #expect(!file.isFolder)
    #expect(file.id == UUID(uuidString: objectID))
    #expect(file.versionID == "v1")
    #expect(file.createdAt != nil)
    #expect(file.updatedAt != nil)
    #expect(file.lastAccessedAt != nil)
    #expect(file.userMetadata == ["owner": "me"])
    #expect(file.isVersioned == true)
    #expect(file.isDeleteMarker == false)
    #expect(file.archivedAt == nil)
    #expect(file.metadata?.eTag == "\"abc\"")
    #expect(file.metadata?.size == 42)
    #expect(file.metadata?.mimeType == "image/png")
    #expect(file.metadata?.cacheControl == .maxAge(.seconds(3600)))
    #expect(file.metadata?.lastModified != nil)
    #expect(file.metadata?.contentLength == 42)
    #expect(file.metadata?.additional == ["httpStatusCode": 200])
  }

  @Test
  func listOptionsReachTheBody() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: "[]").from("avatars")

    let objects: [StorageObject] = try await bucket.list(
      options: ListOptions(
        limit: 10, offset: 20, sortBy: .updatedAt, order: .descending, search: "ava",
        exactMatch: true, versions: .include, deleteMarkers: .only))

    #expect(objects.isEmpty)
    #expect(
      recorder.lastJSON == [
        "prefix": "", "limit": 10, "offset": 20,
        "sortBy": ["column": "updated_at", "order": "desc"],
        "search": "ava", "exactMatch": true, "noncurrentVersions": "include",
        "deleteMarkers": "only",
      ])
  }

  @Test
  func sortColumnsAndVersionFiltersAreOpenSets() {
    let column: ObjectSortColumn = "size"
    let filter: VersionFilter = "future"

    #expect(column == ObjectSortColumn(rawValue: "size"))
    #expect(ObjectSortColumn.name.rawValue == "name")
    #expect(ObjectSortColumn.createdAt.rawValue == "created_at")
    #expect(ObjectSortColumn.lastAccessedAt.rawValue == "last_accessed_at")
    #expect(filter == VersionFilter(rawValue: "future"))
    #expect(VersionFilter.exclude.rawValue == "exclude")
  }

  @Test
  func infoWithVersionIDReturnsObjectInfo() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: infoResponse).from("avatars")

    let info = try await bucket.info(path: "a.png", versionID: "v1")

    #expect(recorder.last?.httpMethod == "GET")
    #expect(
      recorder.lastURL == "http://localhost:54321/storage/v1/object/info/avatars/a.png?versionId=v1"
    )
    #expect(info.id == UUID(uuidString: objectID))
    #expect(info.versionID == "v1")
    #expect(info.name == "a.png")
    #expect(info.bucketID == "avatars")
    #expect(info.size == 42)
    #expect(info.contentType == "image/png")
    #expect(info.cacheControl == .noCache)
    #expect(info.eTag == "\"abc\"")
    #expect(info.lastModified != nil)
    #expect(info.createdAt != nil)
    #expect(info.updatedAt == nil)
    #expect(info.lastAccessedAt == nil)
    #expect(info.userMetadata == ["owner": "me"])
    #expect(info.isVersioned == true)
    #expect(info.isDeleteMarker == nil)
    #expect(info.archivedAt == nil)

    let current: ObjectInfo = try await bucket.info(path: "a.png")
    #expect(current.name == "a.png")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/info/avatars/a.png")
  }

  @Test
  func rowsWithoutTheVersioningFieldsDecode() async throws {
    let recorder = RequestRecorder()

    let listing = recorder.client(
      response: #"[{"name":"a.png","id":"\#(objectID)","metadata":{"size":42}}]"#
    ).from("avatars")
    let object = try #require(try await listing.list(options: ListOptions()).first)
    #expect(object.versionID == nil)
    #expect(object.userMetadata == nil)
    #expect(object.isVersioned == nil)
    #expect(object.isDeleteMarker == nil)
    #expect(object.archivedAt == nil)
    #expect(object.metadata?.size == 42)

    let describing = recorder.client(response: #"{"id":"\#(objectID)","name":"a.png"}"#)
      .from("avatars")
    let info: ObjectInfo = try await describing.info(path: "a.png")
    #expect(info.versionID == "")
    #expect(info.userMetadata == nil)
    #expect(info.isVersioned == nil)
    #expect(info.isDeleteMarker == nil)
    #expect(info.archivedAt == nil)
  }

  @Test
  func moveSendsTheDestinationBucketAndTheSourceVersion() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client().from("avatars")

    try await bucket.move(from: "a.png", to: "b.png", toBucket: "archive", sourceVersionID: "v1")

    #expect(recorder.last?.httpMethod == "POST")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/move")
    #expect(
      recorder.lastJSON == [
        "bucketId": "avatars", "sourceKey": "a.png", "destinationKey": "b.png",
        "destinationBucket": "archive", "sourceVersionId": "v1",
      ])
  }

  @Test
  func copyWithOptionsReturnsAnUploadedObject() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"archive/b.png","Id":"\#(objectID)"}"#)
      .from("avatars")

    let copy = try await bucket.copy(
      from: "a.png", to: "b.png", toBucket: "archive", sourceVersionID: "v1",
      options: CopyOptions(
        upsert: true, copyMetadata: false, metadata: ["owner": "me"], contentType: "image/png",
        cacheControl: .noCache))

    #expect(copy.id == UUID(uuidString: objectID))
    #expect(copy.path == "b.png")
    #expect(copy.fullPath == "archive/b.png")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/copy")
    #expect(recorder.header("x-upsert") == "true")
    #expect(
      recorder.header("x-metadata") == Data(#"{"owner":"me"}"#.utf8).base64EncodedString())
    #expect(
      recorder.lastJSON == [
        "bucketId": "avatars", "sourceKey": "a.png", "destinationKey": "b.png",
        "destinationBucket": "archive", "sourceVersionId": "v1", "copyMetadata": false,
        "metadata": ["cacheControl": "no-cache", "mimetype": "image/png"],
      ])
  }

  @Test
  func copyWithDefaultOptionsSendsOnlyTheKeys() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/b.png"}"#).from("avatars")

    let copy: UploadedObject = try await bucket.copy(from: "a.png", to: "b.png")

    #expect(copy.id == nil)
    #expect(copy.fullPath == "avatars/b.png")
    #expect(recorder.header("x-upsert") == nil)
    #expect(recorder.header("x-metadata") == nil)
    #expect(
      recorder.lastJSON == [
        "bucketId": "avatars", "sourceKey": "a.png", "destinationKey": "b.png",
      ])
  }

  @Test
  func copyCleansTheDestinationPath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/folder/b.png"}"#).from("avatars")

    let copy = try await bucket.copy(from: "a.png", to: "/folder//b.png/", options: CopyOptions())
    #expect(copy.path == "folder/b.png")
    #expect(recorder.lastJSON?["destinationKey"] == "folder/b.png")
    #expect(recorder.lastJSON?["sourceKey"] == "a.png")

    _ = try await bucket.copy(from: "//x//a.png", to: "b.png", options: CopyOptions())
    #expect(recorder.lastJSON?["sourceKey"] == "x/a.png")
    await #expect(throws: StorageError.self) {
      _ = try await bucket.copy(from: "../a.png", to: "b.png", options: CopyOptions())
    }

    let sent = recorder.requests.value.count
    for destination in ["", "//", "folder/../b.png", "./b.png"] {
      do {
        _ = try await bucket.copy(from: "a.png", to: destination, options: CopyOptions())
        Issue.record("Expected a StorageError for '\(destination)'")
      } catch let error as StorageError {
        #expect(error.kind == .invalidRequest)
      }
    }
    #expect(recorder.requests.value.count == sent)
  }

  @Test
  @available(*, deprecated)
  func theV2CopySendsTheDestinationAsGiven() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/b.png"}"#).from("avatars")

    _ = try await bucket.copy(from: "//a.png", to: "/folder//b.png")
    #expect(recorder.lastJSON?["destinationKey"] == "/folder//b.png")
    #expect(recorder.lastJSON?["sourceKey"] == "//a.png")

    try await bucket.move(from: "//a.png", to: "../b.png", options: nil)
    #expect(recorder.lastJSON?["sourceKey"] == "//a.png")
    #expect(recorder.lastJSON?["destinationKey"] == "../b.png")

    let signing = recorder.client(
      response: #"{"url":"/object/upload/sign/avatars/a.png?token=tok"}"#
    ).from("avatars")
    _ = try await signing.createSignedUploadURL(path: "x/../a.png", options: nil)
    #expect(recorder.lastURL?.contains("avatars/x/../a.png") == true)
  }

  private func expectInvalidRequest(_ body: () async throws -> Void) async {
    do {
      try await body()
      Issue.record("Expected a StorageError")
    } catch let error as StorageError {
      #expect(error.kind == .invalidRequest)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func moveCleansBothPaths() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client().from("avatars")

    try await bucket.move(from: "/x//a.png", to: "y/b.png/")
    #expect(recorder.lastJSON?["sourceKey"] == "x/a.png")
    #expect(recorder.lastJSON?["destinationKey"] == "y/b.png")

    await expectInvalidRequest { try await bucket.move(from: "", to: "b.png") }
    await expectInvalidRequest { try await bucket.move(from: "a.png", to: "x/../b.png") }
    #expect(recorder.requests.value.count == 1)
  }

  @Test
  func uploadAndUpdateCleanThePath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/x/a.png","Id":"\#(objectID)"}"#)
      .from("avatars")

    let uploaded = try await bucket.upload(path: "/x//a.png", data: Data("a".utf8))
    #expect(uploaded.path == "x/a.png")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/avatars/x/a.png")
    let updated = try await bucket.update(path: "x/a.png/", data: Data("a".utf8))
    #expect(updated.path == "x/a.png")

    await expectInvalidRequest { _ = try await bucket.upload(path: "./a.png", data: Data()) }
    await expectInvalidRequest { _ = try await bucket.update(path: "/", data: Data()) }
    #expect(recorder.requests.value.count == 2)
  }

  @Test
  func uploadToSignedURLCleansThePath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"Key":"avatars/x/a.png"}"#).from("avatars")

    let uploaded = try await bucket.uploadToSignedURL(
      path: "/x//a.png", token: "tok", data: Data("a".utf8))
    #expect(uploaded.path == "x/a.png")
    #expect(recorder.lastURL?.contains("/object/upload/sign/avatars/x/a.png?") == true)

    await expectInvalidRequest {
      _ = try await bucket.uploadToSignedURL(path: "../a.png", token: "tok", data: Data())
    }
    #expect(recorder.requests.value.count == 1)
  }

  @Test
  func signedURLsCleanThePath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: #"{"signedURL":"/object/sign/avatars/x/a.png?token=t"}"#)
      .from("avatars")

    _ = try await bucket.createSignedURL(path: "/x//a.png", expiresIn: .seconds(60))
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/sign/avatars/x/a.png")
    await expectInvalidRequest {
      _ = try await bucket.createSignedURL(path: "x/./a.png", expiresIn: .seconds(60))
    }

    let many = recorder.client(response: "[]").from("avatars")
    _ = try await many.createSignedURLs(paths: ["/x//a.png", "b.png/"], expiresIn: .seconds(60))
    #expect(recorder.lastJSON?["paths"] == ["x/a.png", "b.png"])
    await expectInvalidRequest {
      _ = try await many.createSignedURLs(paths: ["a.png", ""], expiresIn: .seconds(60))
    }
    #expect(recorder.requests.value.count == 2)
  }

  @Test
  func signedUploadURLCleansThePath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(
      response: #"{"url":"/object/upload/sign/avatars/x/a.png?token=tok"}"#
    ).from("avatars")

    let signed = try await bucket.createSignedUploadURL(path: "/x//a.png", upsert: true)
    #expect(signed.path == "x/a.png")
    #expect(
      recorder.lastURL == "http://localhost:54321/storage/v1/object/upload/sign/avatars/x/a.png")
    await expectInvalidRequest {
      _ = try await bucket.createSignedUploadURL(path: "x/../a.png", upsert: false)
    }
    #expect(recorder.requests.value.count == 1)
  }

  @Test
  func infoListAndPublicURLCleanThePath() async throws {
    let recorder = RequestRecorder()
    let bucket = recorder.client(response: infoResponse).from("avatars")

    _ = try await bucket.info(path: "/x//a.png", versionID: "v1")
    #expect(
      recorder.lastURL
        == "http://localhost:54321/storage/v1/object/info/avatars/x/a.png?versionId=v1")
    await expectInvalidRequest { _ = try await bucket.info(path: "", versionID: "v1") }

    let listing = recorder.client(response: "[]").from("avatars")
    _ = try await listing.list(path: "/users//2024/", options: ListOptions())
    #expect(recorder.lastJSON?["prefix"] == "users/2024")
    _ = try await listing.list(path: "/", options: ListOptions())
    #expect(recorder.lastJSON?["prefix"] == "")
    await expectInvalidRequest {
      _ = try await listing.list(path: "users/..", options: ListOptions())
    }
    #expect(recorder.requests.value.count == 3)

    #expect(
      bucket.publicURL(path: "/x//a.png").absoluteString
        == "http://localhost:54321/storage/v1/object/public/avatars/x/a.png")
    #expect(
      bucket.publicURL(path: "x/../a.png").absoluteString
        == "http://localhost:54321/storage/v1/object/public/avatars/x/../a.png")
  }

  /// The v2 spellings keep their overloads, results and requests.
  @Test
  @available(*, deprecated)
  func v2CallSitesKeepTheV2Overload() async throws {
    let recorder = RequestRecorder()

    let listing = recorder.client(
      response: #"[{"name":"a.png","bucket_id":"avatars","owner":"me"}]"#
    ).from("avatars")
    let files = try await listing.list()
    #expect(files.first?.bucketId == "avatars")
    #expect(
      recorder.lastJSON == [
        "prefix": "", "limit": 100, "offset": 0, "sortBy": ["column": "name", "order": "asc"],
      ])
    let found = try await listing.list(
      path: "users",
      options: SearchOptions(limit: 5, sortBy: SortBy(column: "created_at"), search: "a"))
    #expect(found.first?.owner == "me")
    #expect(
      recorder.lastJSON == [
        "prefix": "users", "limit": 5, "offset": 0, "search": "a",
        "sortBy": ["column": "created_at", "order": "asc"],
      ])

    let describing = recorder.client(response: infoResponse).from("avatars")
    let info = try await describing.info(path: "a.png")
    #expect(info.version == "v1")
    #expect(info.metadata == ["owner": "me"])
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/info/avatars/a.png")

    let copying = recorder.client(response: #"{"Key":"avatars/b.png"}"#).from("avatars")
    let key = try await copying.copy(from: "a.png", to: "b.png")
    #expect(key.hasSuffix("b.png"))
    #expect(
      recorder.lastJSON == [
        "bucketId": "avatars", "sourceKey": "a.png", "destinationKey": "b.png",
        "destinationBucket": nil,
      ])
    let crossKey = try await copying.copy(
      from: "a.png", to: "b.png", options: DestinationOptions(destinationBucket: "archive"))
    #expect(crossKey == "avatars/b.png")
    #expect(recorder.lastJSON?["destinationBucket"] == "archive")

    try await copying.move(from: "a.png", to: "b.png")
    #expect(recorder.lastURL == "http://localhost:54321/storage/v1/object/move")
    #expect(
      recorder.lastJSON == [
        "bucketId": "avatars", "sourceKey": "a.png", "destinationKey": "b.png",
        "destinationBucket": nil,
      ])
    try await copying.move(
      from: "a.png", to: "b.png", options: DestinationOptions(destinationBucket: "archive"))
    #expect(recorder.lastJSON?["destinationBucket"] == "archive")
  }
}
