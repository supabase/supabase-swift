import Foundation
import Testing

@testable import Storage

@Suite
struct StorageTypesTests {
  @Test
  func fileObject_decodesSnakeCaseKeys() throws {
    let data = Data(
      """
      {
        "name": "a.txt",
        "bucket_id": "bucket",
        "owner": "owner",
        "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "updated_at": "2024-01-01T00:00:00.000Z",
        "created_at": "2024-01-01T00:00:00.000Z",
        "last_accessed_at": "2024-01-01T00:00:00.000Z",
        "metadata": { "k": "v" }
      }
      """.utf8
    )

    let decoded = try StorageClientConfiguration.defaultDecoder.decode(FileObject.self, from: data)
    #expect(decoded.name == "a.txt")
    #expect(decoded.bucketId == "bucket")
    #expect(decoded.owner == "owner")
    #expect(decoded.id?.uuidString == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    #expect(decoded.metadata?["k"] == AnyJSON.string("v"))
  }

  @Test
  func bucket_decodesPublicKey() throws {
    let data = Data(
      """
      {
        "id": "bucket",
        "name": "bucket",
        "owner": "owner",
        "public": true,
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
      """.utf8
    )

    let decoded = try StorageClientConfiguration.defaultDecoder.decode(Bucket.self, from: data)
    #expect(decoded.isPublic == true)
  }

  @Test
  func fileObjectV2_decodesSnakeCaseKeys() throws {
    let data = Data(
      """
      {
        "id": "id",
        "version": "v",
        "name": "a.txt",
        "bucket_id": "bucket",
        "updated_at": "2024-01-01T00:00:00.000Z",
        "created_at": "2024-01-01T00:00:00.000Z",
        "last_accessed_at": "2024-01-01T00:00:00.000Z",
        "size": 1,
        "cache_control": "max-age=3600",
        "content_type": "text/plain",
        "etag": "etag",
        "last_modified": "2024-01-01T00:00:00.000Z",
        "metadata": { "k": "v" }
      }
      """.utf8
    )

    let decoded = try StorageClientConfiguration.defaultDecoder.decode(FileObjectV2.self, from: data)
    #expect(decoded.bucketId == "bucket")
    #expect(decoded.cacheControl == "max-age=3600")
    #expect(decoded.contentType == "text/plain")
    #expect(decoded.metadata?["k"] == AnyJSON.string("v"))
  }

  @Test
  func signedURL_decodes() throws {
    let data = Data(
      """
      {
        "signedURL": "https://example.com/file.txt",
        "path": "file.txt"
      }
      """.utf8
    )

    let decoded = try JSONDecoder().decode(SignedURL.self, from: data)
    #expect(decoded.path == "file.txt")
    #expect(decoded.signedURL.absoluteString == "https://example.com/file.txt")
  }

  @Test
  func createSignedUploadURLOptions_init() {
    let options = CreateSignedUploadURLOptions(upsert: true)
    #expect(options.upsert == true)
  }

  @Test
  func destinationOptions_init() {
    let options = DestinationOptions(destinationBucket: "other")
    #expect(options.destinationBucket == "other")
  }
}
