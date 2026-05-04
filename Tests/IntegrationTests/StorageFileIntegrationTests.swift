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

@Suite(.serialized)
struct StorageFileIntegrationTests {
  let storage: StorageClient
  let file: Data

  init() throws {
    storage = StorageClient(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      configuration: StorageClientConfiguration(
        headers: [
          "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
        ],
        logger: nil
      )
    )
    let fixturesURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Upload")
    file = try Data(contentsOf: fixturesURL.appendingPathComponent("sadcat.jpg"))
  }

  // MARK: - URL construction (no network)

  @Test func getPublicURL() throws {
    let bucket = "test-bucket"
    let path = "testpath/file.jpg"
    let publicURL = try storage.from(bucket).getPublicURL(path: path)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucket)/\(path)"
    )
  }

  @Test func getPublicURLWithDownloadQueryString() throws {
    let bucket = "test-bucket"
    let path = "testpath/file.jpg"
    let publicURL = try storage.from(bucket).getPublicURL(path: path, download: .withOriginalName)
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucket)/\(path)?download="
    )
  }

  @Test func getPublicURLWithCustomDownload() throws {
    let bucket = "test-bucket"
    let path = "testpath/file.jpg"
    let publicURL = try storage.from(bucket).getPublicURL(path: path, download: .named("test.jpg"))
    #expect(
      publicURL.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/object/public/\(bucket)/\(path)?download=test.jpg"
    )
  }

  @Test func getPublicURLWithTransformOptions() throws {
    let bucket = "test-bucket"
    let path = "testpath/file.jpg"
    let res = try storage.from(bucket).getPublicURL(
      path: path,
      options: TransformOptions(width: 700, height: 300, quality: 70)
    )
    #expect(
      res.absoluteString
        == "\(DotEnv.SUPABASE_URL)/storage/v1/render/image/public/\(bucket)/\(path)?width=700&height=300&quality=70"
    )
  }

  // MARK: - Network tests

  @Test func signURL() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      _ = try await storage.from(bucket).upload(path, data: file).value

      let url = try await storage.from(bucket).createSignedURL(
        path: path, expiresIn: .seconds(2000))
      #expect(
        url.absoluteString.contains(
          "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucket)/\(path)")
      )
    }
  }

  @Test func signURL_withDownloadQueryString() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      _ = try await storage.from(bucket).upload(path, data: file).value

      let url = try await storage.from(bucket).createSignedURL(
        path: path, expiresIn: .seconds(2000), download: .withOriginalName)
      #expect(
        url.absoluteString.contains(
          "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucket)/\(path)")
      )
      #expect(url.absoluteString.contains("&download="))
    }
  }

  @Test func signURL_withCustomFilenameForDownload() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      _ = try await storage.from(bucket).upload(path, data: file).value

      let url = try await storage.from(bucket).createSignedURL(
        path: path, expiresIn: .seconds(2000), download: .named("test.jpg"))
      #expect(
        url.absoluteString.contains(
          "\(DotEnv.SUPABASE_URL)/storage/v1/object/sign/\(bucket)/\(path)")
      )
      #expect(url.absoluteString.contains("&download=test.jpg"))
    }
  }

  @Test func uploadAndUpdateFile() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let file2 = try Data(contentsOf: uploadFileURL("file-2.txt"))

      try await storage.from(bucket).upload(path, data: file).value

      let res = try await storage.from(bucket).update(path, data: file2).value
      #expect(res.path == path)
    }
  }

  @Test func uploadFileWithinFileSizeLimit() async throws {
    try await withBucket(options: BucketOptions(isPublic: true, fileSizeLimit: .megabytes(1))) {
      bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value
    }
  }

  @Test func uploadFileThatExceedsFileSizeLimit() async throws {
    try await withBucket(options: BucketOptions(isPublic: true, fileSizeLimit: .kilobytes(1))) {
      bucket in
      let path = uploadPath()
      do {
        try await storage.from(bucket).upload(path, data: file).value
        Issue.record("Unexpected success")
      } catch let error as StorageError {
        #expect(error.statusCode == 413)
        #expect(error.message == "The object exceeded the maximum allowed size")
      } catch {
        Issue.record("Unexpected error type: \(error)")
      }
    }
  }

  @Test func uploadFileWithValidMimeType() async throws {
    try await withBucket(options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/jpeg"])) {
      bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(
        path, data: file, options: FileOptions(contentType: "image/jpeg")
      ).value
    }
  }

  @Test func uploadFileWithInvalidMimeType() async throws {
    try await withBucket(options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/png"])) {
      bucket in
      let path = uploadPath()
      do {
        try await storage.from(bucket).upload(
          path, data: file, options: FileOptions(contentType: "image/jpeg")
        ).value
        Issue.record("Unexpected success")
      } catch let error as StorageError {
        #expect(error.statusCode == 415)
        #expect(error.message == "mime type image/jpeg is not supported")
      } catch {
        Issue.record("Unexpected error type: \(error)")
      }
    }
  }

  @Test func signedURLForUpload() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let res = try await storage.from(bucket).createSignedUploadURL(path: path)
      #expect(res.path == path)
      #expect(
        res.signedURL.absoluteString.contains(
          "\(DotEnv.SUPABASE_URL)/storage/v1/object/upload/sign/\(bucket)/\(path)")
      )
    }
  }

  @Test func canUploadWithSignedURLForUpload() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let res = try await storage.from(bucket).createSignedUploadURL(path: path)

      let uploadRes = try await storage.from(bucket).uploadToSignedURL(
        res.path, token: res.token, data: file
      ).value
      #expect(uploadRes.path == path)
    }
  }

  @Test func canUploadOverwritingFilesWithSignedURL() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value

      let res = try await storage.from(bucket).createSignedUploadURL(
        path: path, options: CreateSignedUploadURLOptions(upsert: true))
      let uploadRes = try await storage.from(bucket).uploadToSignedURL(
        res.path, token: res.token, data: file
      ).value
      #expect(uploadRes.path == path)
    }
  }

  @Test func cannotUploadToSignedURLTwice() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let res = try await storage.from(bucket).createSignedUploadURL(path: path)

      try await storage.from(bucket).uploadToSignedURL(res.path, token: res.token, data: file)
        .value

      do {
        try await storage.from(bucket).uploadToSignedURL(res.path, token: res.token, data: file)
          .value
        Issue.record("Unexpected success")
      } catch let error as StorageError {
        #expect(error.statusCode == 409)
        #expect(error.message == "The resource already exists")
      } catch {
        Issue.record("Unexpected error type: \(error)")
      }
    }
  }

  @Test func listObjects() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value
      let res = try await storage.from(bucket).list(path: "testpath")

      #expect(res.count == 1)
      #expect(res[0].name == path.replacingOccurrences(of: "testpath/", with: ""))
    }
  }

  @Test func moveObjectToDifferentPath() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let newPath = "testpath/file-moved-\(UUID().uuidString).txt"
      try await storage.from(bucket).upload(path, data: file).value

      try await storage.from(bucket).move(from: path, to: newPath)
    }
  }

  @Test func moveObjectsAcrossBuckets() async throws {
    try await withBucket { sourceBucket in
      try await withBucket { destBucket in
        let path = uploadPath()
        let newPath = "testpath/file-to-move-\(UUID().uuidString).txt"
        try await storage.from(sourceBucket).upload(path, data: file).value

        try await storage.from(sourceBucket).move(
          from: path,
          to: newPath,
          options: DestinationOptions(destinationBucket: destBucket)
        )

        _ = try await storage.from(destBucket).downloadData(path: newPath).value
      }
    }
  }

  @Test func copyObjectToDifferentPath() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      let newPath = "testpath/file-copied-\(UUID().uuidString).txt"
      try await storage.from(bucket).upload(path, data: file).value

      try await storage.from(bucket).copy(from: path, to: newPath)
    }
  }

  @Test func copyObjectsAcrossBuckets() async throws {
    try await withBucket { sourceBucket in
      try await withBucket { destBucket in
        let path = uploadPath()
        let newPath = "testpath/file-to-copy-\(UUID().uuidString).txt"
        try await storage.from(sourceBucket).upload(path, data: file).value

        try await storage.from(sourceBucket).copy(
          from: path,
          to: newPath,
          options: DestinationOptions(destinationBucket: destBucket)
        )

        _ = try await storage.from(destBucket).downloadData(path: newPath).value
      }
    }
  }

  @Test func downloadsAnObject() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value

      let res = try await storage.from(bucket).downloadData(path: path).value
      #expect(res.count > 0)
    }
  }

  @Test func removesAnObject() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value

      let res = try await storage.from(bucket).remove(paths: [path])
      #expect(res.count == 1)
      #expect(res[0].bucketId == bucket)
      #expect(res[0].name == path)
    }
  }

  @Test func createAndLoadEmptyFolder() async throws {
    try await withBucket { bucket in
      let path = "empty-folder/.placeholder"
      try await storage.from(bucket).upload(path, data: Data()).value

      let files = try await storage.from(bucket).list()
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
  }

  @Test func info() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(
        path, data: file, options: FileOptions(metadata: ["value": 42])
      ).value

      let info = try await storage.from(bucket).info(path: path)
      #expect(info.name == path)
      #expect(info.metadata == ["value": 42])
    }
  }

  @Test func exists() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, data: file).value

      var exists = try await storage.from(bucket).exists(path: path)
      #expect(exists)

      exists = try await storage.from(bucket).exists(path: "invalid.jpg")
      #expect(!exists)
    }
  }

  @Test func uploadWithCacheControl() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(
        path, data: file, options: FileOptions(cacheControl: "14400")
      ).value

      let publicURL = try storage.from(bucket).getPublicURL(path: path)

      let (_, response) = try await URLSession.shared.data(from: publicURL)
      let httpResponse = try #require(response as? HTTPURLResponse)
      let cacheControl = try #require(httpResponse.value(forHTTPHeaderField: "cache-control"))

      #expect(cacheControl == "max-age=14400")
    }
  }

  @Test func uploadWithFileURL() async throws {
    try await withBucket { bucket in
      let path = uploadPath()
      try await storage.from(bucket).upload(path, fileURL: uploadFileURL("sadcat.jpg")).value

      let uploaded = try await storage.from(bucket).downloadData(path: path).value
      #expect(uploaded == file)
    }
  }

  // MARK: - Helpers

  /// Creates a fresh bucket, runs the test body, then cleans up regardless of success or failure.
  private func withBucket(
    options: BucketOptions = BucketOptions(isPublic: true),
    _ body: (String) async throws -> Void
  ) async throws {
    let bucketId = "file-test-\(UUID().uuidString.lowercased())"
    try await storage.createBucket(bucketId, options: options)
    do {
      try await body(bucketId)
    } catch {
      try? await storage.emptyBucket(bucketId)
      try? await storage.deleteBucket(bucketId)
      throw error
    }
    try? await storage.emptyBucket(bucketId)
    try? await storage.deleteBucket(bucketId)
  }

  private func uploadPath() -> String {
    "testpath/file-\(UUID().uuidString).jpg"
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Upload")
      .appendingPathComponent(fileName)
  }
}
