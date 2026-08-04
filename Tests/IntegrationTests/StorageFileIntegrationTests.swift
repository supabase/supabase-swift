//
//  StorageFileIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import InlineSnapshotTesting
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageFileIntegrationTests {
  let storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

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
  func getPublicURL() throws {
    let publicURL = try storage.from(bucketName).getPublicURL(path: uploadPath)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucketName)/\(uploadPath)"
    )
  }

  @Test
  func getPublicURLWithDownloadQueryString() throws {
    let publicURL = try storage.from(bucketName).getPublicURL(path: uploadPath, download: true)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucketName)/\(uploadPath)?download="
    )
  }

  @Test
  func getPublicURLWithCustomDownload() throws {
    let publicURL = try storage.from(bucketName).getPublicURL(
      path: uploadPath, download: "test.jpg")
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucketName)/\(uploadPath)?download=test.jpg"
    )
  }

  @Test
  func signURL() async throws {
    _ = try await storage.from(bucketName).upload(uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(path: uploadPath, expiresIn: 2000)
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
  }

  @Test
  func signURL_withDownloadQueryString() async throws {
    _ = try await storage.from(bucketName).upload(uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: 2000, download: true)
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
    #expect(url.absoluteString.contains("&download="))
  }

  @Test
  func signURL_withCustomFilenameForDownload() async throws {
    _ = try await storage.from(bucketName).upload(uploadPath, data: file)

    let url = try await storage.from(bucketName).createSignedURL(
      path: uploadPath, expiresIn: 2000, download: "test.jpg")
    #expect(
      url.absoluteString.contains(
        "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucketName)/\(uploadPath)")
    )
    #expect(url.absoluteString.contains("&download=test.jpg"))
  }

  @Test
  func uploadAndUpdateFile() async throws {
    let file2 = try Data(contentsOf: uploadFileURL("file-2.txt"))

    try await storage.from(bucketName).upload(uploadPath, data: file)

    let res = try await storage.from(bucketName).update(uploadPath, data: file2)
    #expect(res.path == uploadPath)
  }

  @Test
  func uploadFileWithinFileSizeLimit() async throws {
    bucketName = try await newBucket(
      prefix: "with-limit",
      options: BucketOptions(isPublic: true, fileSizeLimit: .megabytes(1))
    )

    try await storage.from(bucketName).upload(uploadPath, data: file)
  }

  @Test
  func uploadFileThatExceedFileSizeLimit() async throws {
    bucketName = try await newBucket(
      prefix: "with-limit",
      options: BucketOptions(isPublic: true, fileSizeLimit: .kilobytes(1))
    )

    do {
      try await storage.from(bucketName).upload(uploadPath, data: file)
      Issue.record("Unexpected success")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ StorageError
          ▿ error: Optional<String>
            - some: "Payload too large"
          - message: "The object exceeded the maximum allowed size"
          ▿ statusCode: Optional<String>
            - some: "413"

        """
      }
    }
  }

  @Test
  func uploadFileWithValidMimeType() async throws {
    bucketName = try await newBucket(
      prefix: "with-mimetype",
      options: BucketOptions(public: true, allowedMimeTypes: ["image/jpeg"])
    )

    try await storage.from(bucketName).upload(
      uploadPath,
      data: file,
      options: FileOptions(
        contentType: "image/jpeg"
      )
    )
  }

  @Test
  func uploadFileWithInvalidMimeType() async throws {
    bucketName = try await newBucket(
      prefix: "with-mimetype",
      options: BucketOptions(public: true, allowedMimeTypes: ["image/png"])
    )

    do {
      try await storage.from(bucketName).upload(
        uploadPath,
        data: file,
        options: FileOptions(
          contentType: "image/jpeg"
        )
      )
      Issue.record("Unexpected success")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ StorageError
          ▿ error: Optional<String>
            - some: "invalid_mime_type"
          - message: "mime type image/jpeg is not supported"
          ▿ statusCode: Optional<String>
            - some: "415"

        """
      }
    }
  }

  @Test
  func signedURLForUpload() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)
    #expect(res.path == uploadPath)
    #expect(
      res.signedURL.absoluteString.contains(
        "\(DotEnv.SUPABASE_URL)/storage/v1/object/upload/sign/\(bucketName)/\(uploadPath)"
      )
    )
  }

  @Test
  func canUploadWithSignedURLForUpload() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)

    let uploadRes = try await storage.from(bucketName).uploadToSignedURL(
      res.path, token: res.token, data: file)
    #expect(uploadRes.path == uploadPath)
  }

  @Test
  func canUploadOverwritingFilesWithSignedURL() async throws {
    try await storage.from(bucketName).upload(uploadPath, data: file)

    let res = try await storage.from(bucketName).createSignedUploadURL(
      path: uploadPath, options: CreateSignedUploadURLOptions(upsert: true))
    let uploadRes = try await storage.from(bucketName).uploadToSignedURL(
      res.path, token: res.token, data: file)
    #expect(uploadRes.path == uploadPath)
  }

  @Test
  func cannotUploadToSignedURLTwice() async throws {
    let res = try await storage.from(bucketName).createSignedUploadURL(path: uploadPath)

    try await storage.from(bucketName).uploadToSignedURL(res.path, token: res.token, data: file)

    do {
      try await storage.from(bucketName).uploadToSignedURL(res.path, token: res.token, data: file)
      Issue.record("Unexpected success")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ StorageError
          ▿ error: Optional<String>
            - some: "Duplicate"
          - message: "The resource already exists"
          ▿ statusCode: Optional<String>
            - some: "409"

        """
      }
    }
  }

  @Test
  func listObjects() async throws {
    try await storage.from(bucketName).upload(uploadPath, data: file)
    let res = try await storage.from(bucketName).list(path: "testpath")

    #expect(res.count == 1)
    #expect(res[0].name == uploadPath.replacingOccurrences(of: "testpath/", with: ""))
  }

  @Test
  func moveObjectToDifferentPath() async throws {
    let newPath = "testpath/file-moved-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(uploadPath, data: file)

    try await storage.from(bucketName).move(from: uploadPath, to: newPath)
  }

  @Test
  func moveObjectsAcrossBucketsInDifferentPath() async throws {
    let newBucketName = "bucket-move"
    try await findOrCreateBucket(name: newBucketName)

    let newPath = "testpath/file-to-move-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(uploadPath, data: file)

    try await storage.from(bucketName).move(
      from: uploadPath,
      to: newPath,
      options: DestinationOptions(destinationBucket: newBucketName)
    )

    _ = try await storage.from(newBucketName).download(path: newPath)
  }

  @Test
  func copyObjectToDifferentPath() async throws {
    let newPath = "testpath/file-moved-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(uploadPath, data: file)

    try await storage.from(bucketName).copy(from: uploadPath, to: newPath)
  }

  @Test
  func copyObjectsAcrossBucketsInDifferentPath() async throws {
    let newBucketName = "bucket-copy"
    try await findOrCreateBucket(name: newBucketName)

    let newPath = "testpath/file-to-copy-\(UUID().uuidString).txt"
    try await storage.from(bucketName).upload(uploadPath, data: file)

    try await storage.from(bucketName).copy(
      from: uploadPath,
      to: newPath,
      options: DestinationOptions(destinationBucket: newBucketName)
    )

    _ = try await storage.from(newBucketName).download(path: newPath)
  }

  @Test
  func downloadsAnObject() async throws {
    try await storage.from(bucketName).upload(uploadPath, data: file)

    let res = try await storage.from(bucketName).download(path: uploadPath)
    #expect(res.count > 0)
  }

  @Test
  func removesAnObject() async throws {
    try await storage.from(bucketName).upload(uploadPath, data: file)

    let res = try await storage.from(bucketName).remove(paths: [uploadPath])
    #expect(res.count == 1)
    #expect(res[0].bucketId == bucketName)
    #expect(res[0].name == uploadPath)
  }

  @Test
  func getPublishURLWithTransformationOptions() throws {
    let res = try storage.from(bucketName).getPublicURL(
      path: uploadPath,
      options: TransformOptions(
        width: 700,
        height: 300,
        quality: 70
      )
    )

    #expect(
      res.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/render/image/public/\(bucketName)/\(uploadPath)?width=700&height=300&quality=70"
    )
  }

  @Test
  func createAndLoadEmptyFolder() async throws {
    let path = "empty-folder/.placeholder"
    try await storage.from(bucketName).upload(path, data: Data())

    let files = try await storage.from(bucketName).list()
    assertInlineSnapshot(of: files, as: .json) {
      """
      [
        {
          "name" : "empty-folder"
        }
      ]
      """
    }
  }

  @Test
  func info() async throws {
    try await storage.from(bucketName).upload(
      uploadPath,
      data: file,
      options: FileOptions(
        metadata: ["value": 42]
      )
    )

    let info = try await storage.from(bucketName).info(path: uploadPath)
    #expect(info.name == uploadPath)
    #expect(info.metadata == ["value": 42])
  }

  @Test
  func exists() async throws {
    try await storage.from(bucketName).upload(uploadPath, data: file)

    var exists = try await storage.from(bucketName).exists(path: uploadPath)
    #expect(exists)

    exists = try await storage.from(bucketName).exists(path: "invalid.jpg")
    #expect(!exists)
  }

  @Test
  func uploadWithCacheControl() async throws {
    try await storage.from(bucketName).upload(
      uploadPath,
      data: file,
      options: FileOptions(
        cacheControl: "14400"
      )
    )

    let publicURL = try storage.from(bucketName).getPublicURL(path: uploadPath)

    let (_, response) = try await URLSession.shared.data(from: publicURL)
    let httpResponse = try #require(response as? HTTPURLResponse)
    let cacheControl = try #require(httpResponse.value(forHTTPHeaderField: "cache-control"))

    #expect(cacheControl == "max-age=14400")
  }

  @Test
  func uploadWithFileURL() async throws {
    try await storage.from(bucketName)
      .upload(uploadPath, fileURL: uploadFileURL("sadcat.jpg"))

    let uploadedFile = try await storage.from(bucketName).download(path: uploadPath)

    #expect(uploadedFile == file)
  }

  private func newBucket(
    prefix: String = "",
    options: BucketOptions = BucketOptions(public: true)
  ) async throws -> String {
    let bucketName = "\(!prefix.isEmpty ? prefix + "-" : "")bucket-\(UUID().uuidString)"
    return try await findOrCreateBucket(name: bucketName, options: options)
  }

  @discardableResult
  private func findOrCreateBucket(
    name: String,
    options: BucketOptions = BucketOptions(public: true)
  ) async throws -> String {
    do {
      _ = try await storage.getBucket(name)
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
