//
//  StorageBucketIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Helpers
import InlineSnapshotTesting
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageBucketIntegrationTests {
  let storage = StorageIntegration.client()

  var bucketName = ""
  var file = Data()
  var uploadPath = ""

  init() async throws {
    bucketName = try await newBucket()
    file = try Data(contentsOf: uploadFileURL("sadcat.jpg"))
    uploadPath = "testpath/file-\(UUID().uuidString).jpg"
  }

  // Async cleanup can outlive the test if the process exits immediately after — acceptable for
  // local dev/CI cleanup, not correctness-critical.
  deinit {
    let storage = storage
    let bucketName = bucketName
    Task {
      try? await storage.emptyBucket(bucketName)
      try? await storage.deleteBucket(bucketName)
    }
  }

  @Test
  func publicURL() throws {
    let publicURL = storage.from(bucketName).publicURL(path: uploadPath)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/object/public/\(bucketName)/\(uploadPath)"
    )
  }

  @Test
  func getPublicURLWithDownloadQueryString() throws {
    let publicURL = storage.from(bucketName).publicURL(
      path: uploadPath, download: .withOriginalName)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/object/public/\(bucketName)/\(uploadPath)?download="
    )
  }

  @Test
  func getPublicURLWithCustomDownload() throws {
    let publicURL = storage.from(bucketName).publicURL(
      path: uploadPath, download: .named("test.jpg"))
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/object/public/\(bucketName)/\(uploadPath)?download=test.jpg"
    )
  }

  @Test
  func signURL() async throws {
    _ = try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: .seconds(2000))
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.supabaseURL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
  }

  @Test
  func signURL_withDownloadQueryString() async throws {
    _ = try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: .seconds(2000), download: .withOriginalName)
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.supabaseURL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
    #expect(url.absoluteString.contains("&download="))
  }

  @Test
  func signURL_withCustomFilenameForDownload() async throws {
    _ = try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: .seconds(2000), download: .named("test.jpg"))
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.supabaseURL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
    #expect(url.absoluteString.contains("&download=test.jpg"))
  }

  @Test
  func uploadAndUpdateFile() async throws {
    let file2 = try Data(contentsOf: uploadFileURL("file-2.txt"))

    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let res = try await storage.from(bucketName).update(path: uploadPath, data: file2)
    #expect(res.path == uploadPath)
  }

  @Test
  func uploadFileWithinFileSizeLimit() async throws {
    bucketName = try await newBucket(
      prefix: "with-limit",
      options: BucketOptions(isPublic: true, fileSizeLimit: .megabytes(1))
    )

    try await storage.from(bucketName).upload(path: uploadPath, data: file)
  }

  @Test
  func uploadFileThatExceedFileSizeLimit() async throws {
    bucketName = try await newBucket(
      prefix: "with-limit",
      options: BucketOptions(isPublic: true, fileSizeLimit: .kilobytes(1))
    )

    do {
      try await storage.from(bucketName).upload(path: uploadPath, data: file)
      Issue.record("Unexpected success")
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.serverError?.error == "Payload too large")
      #expect(error.serverError?.code == .entityTooLarge)
      #expect(error.message == "The object exceeded the maximum allowed size")
      // Storage answers with HTTP 400 and puts "413" in the body.
      #expect(error.serverStatusCode == 413)
      #expect(error.response != nil)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func uploadFileWithValidMimeType() async throws {
    bucketName = try await newBucket(
      prefix: "with-mimetype",
      options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/jpeg"])
    )

    try await storage.from(bucketName).upload(
      path: uploadPath,
      data: file,
      options: UploadOptions(
        contentType: "image/jpeg"
      )
    )
  }

  @Test
  func uploadFileWithInvalidMimeType() async throws {
    bucketName = try await newBucket(
      prefix: "with-mimetype",
      options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/png"])
    )

    do {
      try await storage.from(bucketName).upload(
        path: uploadPath,
        data: file,
        options: UploadOptions(
          contentType: "image/jpeg"
        )
      )
      Issue.record("Unexpected success")
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.serverError?.error == "invalid_mime_type")
      #expect(error.serverError?.code == .invalidMimeType)
      #expect(error.message == "mime type image/jpeg is not supported")
      // Storage answers with HTTP 400 and puts "415" in the body.
      #expect(error.serverStatusCode == 415)
      #expect(error.response != nil)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func signedURLForUpload() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)
    #expect(res.path == uploadPath)
    #expect(
      res.signedURL.absoluteString.contains(
        "\(DotEnv.supabaseURL)/storage/v1/object/upload/sign/\(bucketName)/\(uploadPath)"
      )
    )
  }

  @Test
  func canUploadWithSignedURLForUpload() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)

    let uploadRes = try await storage.from(bucketName).uploadToSignedURL(
      path: res.path, token: res.token, data: file)
    #expect(uploadRes.path == uploadPath)
  }

  @Test
  func canUploadOverwritingFilesWithSignedURL() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let res = try await storage.from(bucketName).createSignedUploadURL(
      path: uploadPath, upsert: true)
    let uploadRes = try await storage.from(bucketName).uploadToSignedURL(
      path: res.path, token: res.token, data: file)
    #expect(uploadRes.path == uploadPath)
  }

  @Test
  func cannotUploadToSignedURLTwice() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)

    try await storage.from(bucketName).uploadToSignedURL(
      path: res.path, token: res.token, data: file)

    do {
      try await storage.from(bucketName).uploadToSignedURL(
        path: res.path, token: res.token, data: file)
      Issue.record("Unexpected success")
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.serverError?.error == "Duplicate")
      #expect(error.serverError?.code == .keyAlreadyExists)
      #expect(error.message == "The resource already exists")
      // Storage answers with HTTP 400 and puts "409" in the body.
      #expect(error.serverStatusCode == 409)
      #expect(error.response != nil)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func listObjects() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)
    let res = try await storage.from(bucketName).list(path: "testpath")

    #expect(res.count == 1)
    #expect(res[0].name == uploadPath.replacingOccurrences(of: "testpath/", with: ""))
  }

  @Test
  func moveObjectToDifferentPath() async throws {
    let newPath = "testpath/file-moved-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    try await storage.from(bucketName).move(from: uploadPath, to: newPath)
  }

  @Test
  func moveObjectsAcrossBucketsInDifferentPath() async throws {
    let newBucketName = "bucket-move"
    try await findOrCreateBucket(name: newBucketName)

    let newPath = "testpath/file-to-move-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    try await storage.from(bucketName).move(
      from: uploadPath,
      to: newPath,
      toBucket: newBucketName
    )

    _ = try await storage.from(newBucketName).download(path: newPath)
  }

  @Test
  func copyObjectToDifferentPath() async throws {
    let newPath = "testpath/file-moved-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    try await storage.from(bucketName).copy(from: uploadPath, to: newPath)
  }

  @Test
  func copyObjectsAcrossBucketsInDifferentPath() async throws {
    let newBucketName = "bucket-copy"
    try await findOrCreateBucket(name: newBucketName)

    let newPath = "testpath/file-to-copy-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    try await storage.from(bucketName).copy(
      from: uploadPath,
      to: newPath,
      toBucket: newBucketName
    )

    _ = try await storage.from(newBucketName).download(path: newPath)
  }

  @Test
  func downloadsAnObject() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let res = try await storage.from(bucketName).download(path: uploadPath).data()
    #expect(res.count > 0)
  }

  @Test
  func removesAnObject() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let res = try await storage.from(bucketName).remove(paths: [uploadPath])
    #expect(res.count == 1)
    #expect(res[0].name == uploadPath)
  }

  @Test
  func getPublishURLWithTransformationOptions() throws {
    let res = storage.from(bucketName).publicURL(
      path: uploadPath,
      transform: ImageTransform(
        width: 700,
        height: 300,
        quality: 70
      )
    )

    #expect(
      res.absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/render/image/public/\(bucketName)/\(uploadPath)?width=700&height=300&quality=70"
    )
  }

  @Test
  func createAndLoadEmptyFolder() async throws {
    let path = "empty-folder/.placeholder"
    try await storage.from(bucketName).upload(path: path, data: Data())

    let files = try await storage.from(bucketName).list()
    #expect(files.map(\.name) == ["empty-folder"])
    #expect(files.allSatisfy { $0.id == nil })
  }

  @Test
  func info() async throws {
    try await storage.from(bucketName).upload(
      path: uploadPath,
      data: file,
      options: UploadOptions(
        metadata: ["value": 42]
      )
    )

    let info = try await storage.from(bucketName).info(path: uploadPath)
    #expect(info.name == uploadPath)
    #expect(info.userMetadata == ["value": 42])
  }

  @Test
  func exists() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    var exists = try await storage.from(bucketName).exists(path: uploadPath)
    #expect(exists)

    exists = try await storage.from(bucketName).exists(path: "invalid.jpg")
    #expect(!exists)
  }

  @Test
  func uploadWithCacheControl() async throws {
    try await storage.from(bucketName).upload(
      path: uploadPath,
      data: file,
      options: UploadOptions(
        cacheControl: .maxAge(.seconds(14400))
      )
    )

    let publicURL = storage.from(bucketName).publicURL(path: uploadPath)

    let (_, response) = try await URLSession.shared.data(from: publicURL)
    let httpResponse = try #require(response as? HTTPURLResponse)
    let cacheControl = try #require(httpResponse.value(forHTTPHeaderField: "cache-control"))

    #expect(cacheControl == "max-age=14400")
  }

  @Test
  func uploadWithFileURL() async throws {
    try await storage.from(bucketName)
      .upload(path: uploadPath, fileURL: uploadFileURL("sadcat.jpg"))

    let uploadedFile = try await storage.from(bucketName).download(path: uploadPath).data()

    #expect(uploadedFile == file)
  }

  // MARK: - Object keys

  /// Every character Storage accepts in a key, plus the normalization the SDK applies before
  /// sending: a leading slash and doubled slashes go away, the rest is sent percent-encoded so
  /// the server reads back exactly the key the caller meant.
  static let acceptedKeys: [(input: String, key: String)] = [
    ("folder/my file.png", "folder/my file.png"),
    ("a+b.png", "a+b.png"),
    ("a?b.png", "a?b.png"),
    ("a;b=c&d.png", "a;b=c&d.png"),
    ("a:b@c!d$e'(f)*g,h.png", "a:b@c!d$e'(f)*g,h.png"),
    ("/leading/slash.png", "leading/slash.png"),
    ("double//slash/x.png", "double/slash/x.png"),
    ("trailing/slash.png/", "trailing/slash.png"),
  ]

  @Test(arguments: acceptedKeys)
  func roundTripsAnAcceptedKeyThroughEveryRoute(input: String, key: String) async throws {
    let api = storage.from(bucketName)
    let payload = Data("hello storage".utf8)
    let folder = key.split(separator: "/").dropLast().joined(separator: "/")
    let leaf = String(key.split(separator: "/").last!)

    let uploaded = try await api.upload(path: input, data: payload)
    #expect(uploaded.path == key)
    #expect(uploaded.fullPath == "\(bucketName)/\(key)")
    #expect(uploaded.id != nil)

    #expect(try await api.exists(path: input))
    #expect(try await api.info(path: input).name == key)
    #expect(try await api.download(path: input).data() == payload)
    #expect(try await api.list(path: folder).map(\.name).contains(leaf))

    let (publicBytes, publicResponse) = try await StorageIntegration.fetch(
      api.publicURL(path: input))
    #expect(publicResponse.statusCode == 200)
    #expect(publicBytes == payload)

    let signed = try await api.createSignedURL(path: input, expiresIn: .seconds(60))
    #expect(
      signed.path(percentEncoded: true).hasSuffix(
        "/object/sign/\(bucketName)/\(key.percentEncodedKey)"))
    // Storage signs the percent-encoded key but verifies against the decoded one, so a key
    // with `+` or `?` cannot be fetched through its signed URL (storage-js has the same limit).
    if !key.contains("+") && !key.contains("?") {
      let (signedBytes, signedResponse) = try await StorageIntegration.fetch(signed)
      #expect(signedResponse.statusCode == 200)
      #expect(signedBytes == payload)
    }

    let copied = try await api.copy(from: input, to: "\(key).copy")
    #expect(copied == "\(bucketName)/\(key).copy")
    try await api.move(from: "\(key).copy", to: "\(key).moved")
    #expect(try await api.exists(path: "\(key).moved"))
    #expect(try await !api.exists(path: "\(key).copy"))

    let removed = try await api.remove(paths: [input, "\(key).moved"])
    #expect(removed.map(\.name).sorted() == [key, "\(key).moved"].sorted())
    #expect(try await !api.exists(path: input))
  }

  /// Keys the server refuses: the SDK sends them encoded, so the server sees the original key,
  /// validates it, and answers with `InvalidKey` rather than a mangled lookup.
  @Test(arguments: ["a#b.png", "100%.png", "café/文件.png", "tilde~.png"])
  func serverRejectsAKeyItDoesNotAllow(input: String) async throws {
    let error = await StorageIntegration.storageError {
      try await storage.from(bucketName).upload(path: input, data: file)
    }

    #expect(error?.kind == .server)
    #expect(error?.code == .invalidKey)
    #expect(error?.serverStatusCode == 400)
    #expect(error?.message == "Invalid key: \(input)")
  }

  @Test(arguments: ["", "/", "//", "a/../b.png", "./a.png", "folder/./a.png"])
  func refusesAnInvalidPathWithoutARequest(input: String) async throws {
    let error = await StorageIntegration.storageError {
      _ = try await storage.from(bucketName).download(path: input)
    }

    #expect(error?.kind == .invalidRequest)
    #expect(error?.response == nil)
  }

  @Test
  func listAcceptsAnyFolderSpelling() async throws {
    let api = storage.from(bucketName)
    try await api.upload(path: "nested/deeper/a.txt", data: file)

    for prefix in ["nested/deeper", "/nested/deeper", "nested//deeper/", "nested/deeper/"] {
      #expect(try await api.list(path: prefix).map(\.name) == ["a.txt"], "prefix \(prefix)")
    }
    #expect(try await api.list(path: "nested").map(\.name) == ["deeper"])
    #expect(try await api.list().map(\.name) == ["nested"])
    #expect(try await api.list(path: "/").map(\.name) == ["nested"])
  }

  // MARK: - Errors

  /// Storage answers with HTTP 400 and puts the real status in the body; the SDK promotes it.
  @Test
  func missingObjectIsNoSuchKey() async throws {
    let api = storage.from(bucketName)

    let operations: [() async throws -> Void] = [
      { _ = try await api.download(path: "missing.png") },
      { _ = try await api.info(path: "missing.png") },
      { try await api.move(from: "missing.png", to: "x.png") },
      { _ = try await api.copy(from: "missing.png", to: "x.png") },
    ]
    for operation in operations {
      let error = await StorageIntegration.storageError(operation)
      #expect(error?.kind == .server)
      #expect(error?.code == .noSuchKey)
      #expect(error?.serverStatusCode == 404)
      #expect(error?.response?.statusCode == 400)
      #expect(error?.isNotFound == true)
      #expect(error?.serverError?.error == "not_found")
      #expect(error?.message == "Object not found")
    }
  }

  @Test
  func removingAMissingObjectIsNotAnError() async throws {
    #expect(try await storage.from(bucketName).remove(paths: ["missing.png"]).isEmpty)
  }

  @Test
  func existsIsFalseOnlyForAMissingKey() async throws {
    let api = storage.from(bucketName)
    try await api.upload(path: "present.txt", data: file)

    #expect(try await api.exists(path: "present.txt"))
    #expect(try await api.exists(path: "present.txt/"))  // normalized to the same key
    #expect(try await !api.exists(path: "absent.txt"))

    let error = await StorageIntegration.storageError {
      _ = try await storage.from("no-such-bucket-\(UUID().uuidString)").exists(path: "x.txt")
    }
    #expect(error?.code == .noSuchBucket)
    #expect(error?.isNotFound == true)
    #expect(error?.serverStatusCode == 404)
  }

  @Test
  func duplicateUploadIsKeyAlreadyExistsWithoutUpsert() async throws {
    let api = storage.from(bucketName)
    try await api.upload(path: uploadPath, data: file)

    let error = await StorageIntegration.storageError {
      try await api.upload(path: uploadPath, data: file)
    }
    #expect(error?.code == .keyAlreadyExists)
    #expect(error?.serverStatusCode == 409)
    #expect(error?.serverError?.error == "Duplicate")

    let replacement = Data("replacement".utf8)
    try await api.upload(path: uploadPath, data: replacement, options: UploadOptions(upsert: true))
    #expect(try await api.download(path: uploadPath).data() == replacement)
  }

  /// Row level security: the anon role reads an empty listing and cannot write.
  @Test
  func anonRoleIsFilteredByRowLevelSecurity() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)
    let anon = StorageIntegration.client(headers: [
      .authorization: "Bearer \(DotEnv.supabasePublishableKey)",
      .init("apikey")!: DotEnv.supabasePublishableKey,
    ])

    #expect(try await anon.from(bucketName).list().isEmpty)

    let error = await StorageIntegration.storageError {
      try await anon.from(bucketName).upload(path: "anon.txt", data: file)
    }
    #expect(error?.code == .accessDenied)
    #expect(error?.serverStatusCode == 403)
    #expect(error?.message == "new row violates row-level security policy")
  }

  // MARK: - Upload options and object types

  @Test
  func uploadStoresEveryOption() async throws {
    let api = storage.from(bucketName)
    let payload = Data("upload payload".utf8)
    let metadata: [String: JSONValue] = ["value": 42, "tag": "options", "flags": [true, false]]

    let uploaded = try await api.upload(
      path: "options.txt",
      data: payload,
      options: UploadOptions(contentType: "text/plain", cacheControl: .noCache, metadata: metadata))
    #expect(uploaded.path == "options.txt")
    #expect(uploaded.fullPath == "\(bucketName)/options.txt")

    let info = try await api.info(path: "options.txt")
    #expect(info.id == uploaded.id)
    #expect(info.name == "options.txt")
    #expect(info.bucketId == bucketName)
    #expect(info.size == Int64(payload.count))
    #expect(info.contentType == "text/plain")
    #expect(info.cacheControl == "no-cache")
    #expect(info.userMetadata == metadata)
    #expect(info.eTag != nil)
    #expect(info.lastModified != nil)
    #expect(info.createdAt != nil)
    #expect(!info.version.isEmpty)

    let (_, response) = try await StorageIntegration.fetch(api.publicURL(path: "options.txt"))
    #expect(response.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
    #expect(response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/plain") == true)
    #expect(response.value(forHTTPHeaderField: "ETag") == info.eTag)
  }

  @Test(arguments: [
    (CacheControl.maxAge(.seconds(90)), "max-age=90"),
    (.maxAge(.milliseconds(2500)), "max-age=2"),
    (.noStore, "no-store"),
    ("max-age=60, s-maxage=600", "max-age=60, s-maxage=600"),
  ])
  func cacheControlIsSentVerbatim(cacheControl: CacheControl, header: String) async throws {
    let api = storage.from(bucketName)
    let path = "cache-\(UUID().uuidString).txt"

    try await api.upload(path: path, data: file, options: UploadOptions(cacheControl: cacheControl))

    #expect(try await api.info(path: path).cacheControl == header)
    let (_, response) = try await StorageIntegration.fetch(api.publicURL(path: path))
    #expect(response.value(forHTTPHeaderField: "Cache-Control") == header)
  }

  @Test
  func listReturnsTypedMetadataAndFolderRows() async throws {
    let api = storage.from(bucketName)
    let payload = Data("listed".utf8)
    try await api.upload(
      path: "listing/a.txt", data: payload, options: UploadOptions(contentType: "text/plain"))
    try await api.upload(path: "listing/sub/b.txt", data: payload)

    let rows = try await api.list(path: "listing")
    #expect(Set(rows.map(\.name)) == ["sub", "a.txt"])

    let fileRow = try #require(rows.first { $0.name == "a.txt" })
    #expect(fileRow.id != nil)
    #expect(!fileRow.isFolder)
    #expect(fileRow.version != nil)
    #expect(fileRow.createdAt != nil)
    #expect(fileRow.updatedAt != nil)
    let metadata = try #require(fileRow.metadata)
    #expect(metadata.size == Int64(payload.count))
    #expect(metadata.contentLength == Int64(payload.count))
    #expect(metadata.mimeType == "text/plain")
    #expect(metadata.cacheControl == "max-age=3600")
    #expect(metadata.eTag != nil)
    #expect(metadata.lastModified != nil)
    #expect(metadata.additional["httpStatusCode"] == 200)

    let folder = try #require(rows.first { $0.name == "sub" })
    #expect(folder.id == nil)
    #expect(folder.isFolder)
    #expect(folder.metadata == nil)
  }

  @Test
  func updateOverwritesAndCreates() async throws {
    let api = storage.from(bucketName)
    let replacement = Data("replacement bytes".utf8)
    try await api.upload(path: uploadPath, data: file)

    let updated = try await api.update(
      path: uploadPath, data: replacement, options: UploadOptions(contentType: "text/plain"))
    #expect(updated.path == uploadPath)
    #expect(try await api.download(path: uploadPath).data() == replacement)
    #expect(try await api.info(path: uploadPath).size == Int64(replacement.count))

    // The server's PUT creates a missing object; the SDK does not pre-check.
    try await api.update(path: "created-by-update.txt", data: file)
    #expect(try await api.exists(path: "created-by-update.txt"))
  }

  @Test
  func extraHeadersReachTheServer() async throws {
    let api = storage.from(bucketName)

    // `x-metadata` set by hand (base64 of {"via":"header"}) reaches the server unchanged.
    try await api.upload(
      path: "header.txt", data: file,
      options: UploadOptions(headers: [.init("x-metadata")!: "eyJ2aWEiOiJoZWFkZXIifQ=="]))

    #expect(try await api.info(path: "header.txt").userMetadata == ["via": "header"])
  }

  @Test
  func fileURLUploadInfersTheContentType() async throws {
    let api = storage.from(bucketName)

    let uploaded = try await api.upload(path: "cat.jpg", fileURL: uploadFileURL("sadcat.jpg"))
    #expect(uploaded.id != nil)

    let info = try await api.info(path: "cat.jpg")
    #if canImport(UniformTypeIdentifiers)
      #expect(info.contentType == "image/jpeg")
    #else
      // Linux has no type database yet (SDK-2043); the upload falls back to a generic type.
      #expect(info.contentType == "application/octet-stream")
    #endif
    #expect(info.size == Int64(file.count))
  }

  @Test
  func signedUploadRoundTrip() async throws {
    let api = storage.from(bucketName)

    let signed = try await api.createSignedUploadURL(path: "signed.txt")
    #expect(signed.path == "signed.txt")
    #expect(!signed.token.isEmpty)
    #expect(signed.signedURL.path.hasSuffix("/object/upload/sign/\(bucketName)/signed.txt"))

    let uploaded = try await api.uploadToSignedURL(
      path: signed.path, token: signed.token, data: file,
      options: UploadOptions(contentType: "text/plain", metadata: ["via": "signed-url"]))
    #expect(uploaded.path == "signed.txt")
    #expect(uploaded.fullPath == "\(bucketName)/signed.txt")

    let info = try await api.info(path: "signed.txt")
    #expect(info.contentType == "text/plain")
    #expect(info.userMetadata == ["via": "signed-url"])
    #expect(try await api.download(path: "signed.txt").data() == file)
  }

  // MARK: - Signed and public URLs

  @Test
  func signedURLServesTheObjectUntilItExpires() async throws {
    let api = storage.from(bucketName)
    try await api.upload(path: uploadPath, data: file)

    let url = try await api.createSignedURL(path: uploadPath, expiresIn: .seconds(1))
    #expect(url.host == StorageIntegration.url.host)
    #expect(url.path.hasSuffix("/object/sign/\(bucketName)/\(uploadPath)"))
    let (bytes, response) = try await StorageIntegration.fetch(url)
    #expect(response.statusCode == 200)
    #expect(bytes == file)

    try await Task.sleep(for: .seconds(3))
    let (expiredBody, expired) = try await StorageIntegration.fetch(url)
    #expect(expired.statusCode == 400)
    #expect(String(decoding: expiredBody, as: UTF8.self).contains("InvalidJWT"))
  }

  @Test
  func subSecondExpiryIsRefusedBeforeSending() async throws {
    let api = storage.from(bucketName)

    let operations: [() async throws -> Void] = [
      { _ = try await api.createSignedURL(path: "file.txt", expiresIn: .milliseconds(999)) },
      { _ = try await api.createSignedURLs(paths: ["file.txt"], expiresIn: .zero) },
    ]
    for operation in operations {
      let error = await StorageIntegration.storageError(operation)
      #expect(error?.kind == .invalidRequest)
      #expect(error?.response == nil)
    }
  }

  @Test(arguments: [
    (DownloadBehavior.named("report.txt"), "filename=report.txt"),
    (.withOriginalName, "attachment;"),
  ])
  func downloadBehaviorSetsContentDisposition(download: DownloadBehavior, expected: String)
    async throws
  {
    let api = storage.from(bucketName)
    try await api.upload(path: uploadPath, data: file)

    let signed = try await api.createSignedURL(
      path: uploadPath, expiresIn: .seconds(60), download: download)
    let (_, signedResponse) = try await StorageIntegration.fetch(signed)
    #expect(
      signedResponse.value(forHTTPHeaderField: "Content-Disposition")?.contains(expected) == true)

    let (_, publicResponse) = try await StorageIntegration.fetch(
      api.publicURL(path: uploadPath, download: download))
    #expect(
      publicResponse.value(forHTTPHeaderField: "Content-Disposition")?.contains(expected) == true)
  }

  @Test
  func createSignedURLsReportsEachPath() async throws {
    let api = storage.from(bucketName)
    try await api.upload(path: uploadPath, data: file)

    let results = try await api.createSignedURLs(
      paths: [uploadPath, "missing.txt"], expiresIn: .seconds(60))
    #expect(results.count == 2)

    guard case .success(let path, let signedURL) = results[0] else {
      Issue.record("Expected success for \(uploadPath), got \(results[0])")
      return
    }
    #expect(path == uploadPath)
    let (bytes, _) = try await StorageIntegration.fetch(signedURL)
    #expect(bytes == file)

    guard case .failure(let missingPath, let reason) = results[1] else {
      Issue.record("Expected failure for missing.txt, got \(results[1])")
      return
    }
    #expect(missingPath == "missing.txt")
    #expect(!reason.isEmpty)
  }

  @Test
  func signedURLWithTransformIsAccepted() async throws {
    try await storage.from(bucketName).upload(path: uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: .seconds(60), transform: ImageTransform(width: 10, height: 10))

    #expect(url.query?.contains("token=") == true)
  }

  @Test
  func publicURLNeverThrowsAndEncodesThePath() throws {
    let api = storage.from(bucketName)

    #expect(
      api.publicURL(path: "/folder//my file.png").absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/object/public/\(bucketName)/folder/my%20file.png")
    #expect(
      api.publicURL(path: "a+b.png", download: .named("x y.png")).absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/object/public/\(bucketName)/a%2Bb.png?download=x%20y.png"
    )
    #expect(
      api.publicURL(
        path: "img.png",
        transform: ImageTransform(
          width: 10, resize: .cover, format: .webp, gravity: .focalPoint,
          focalPoint: .init(x: 0.5, y: 0.25))
      ).absoluteString
        == "\(DotEnv.supabaseURL)/storage/v1/render/image/public/\(bucketName)/img.png?width=10&resize=cover&format=webp&gravity=fp&x_offset=0.5&y_offset=0.25"
    )
  }

  private func newBucket(
    prefix: String = "",
    options: BucketOptions = BucketOptions(isPublic: true)
  ) async throws -> String {
    let bucketName = "\(!prefix.isEmpty ? prefix + "-" : "")bucket-\(UUID().uuidString)"
    return try await findOrCreateBucket(name: bucketName, options: options)
  }

  @discardableResult
  private func findOrCreateBucket(
    name: String,
    options: BucketOptions = BucketOptions(isPublic: true)
  ) async throws -> String {
    do {
      _ = try await storage.bucket(name)
    } catch {
      try await storage.createBucket(name, options: options)
    }

    return name
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Upload")
      .appendingPathComponent(fileName)
  }
}
