import Foundation
import HTTPTypes
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

protocol ResumableClient: Sendable {
  static var tusVersion: String { get }

  func createUpload(
    fingerprint: Fingerprint,
    path: String,
    bucketId: String,
    contentLength: Int64,
    contentType: String?,
    upsert: Bool,
    metadata: [String: String]
  ) async throws -> ResumableCacheEntry

  func continueUpload(
    fingerprint: Fingerprint,
    cacheEntry: ResumableCacheEntry
  ) async throws -> ResumableCacheEntry?
}

extension ResumableClient {
  static var tusVersion: String { "1.0.0" }
}

final class ResumableClientImpl: ResumableClient, @unchecked Sendable {
  static let tusVersion = "1.0.0"

  private let storageApi: StorageApi
  private let cache: any ResumableCache

  init(storageApi: StorageApi, cache: any ResumableCache) {
    self.storageApi = storageApi
    self.cache = cache
  }

  func createUpload(
    fingerprint: Fingerprint,
    path: String,
    bucketId: String,
    contentLength: Int64,
    contentType: String?,
    upsert: Bool,
    metadata: [String: String]
  ) async throws -> ResumableCacheEntry {
    var uploadMetadata = metadata
    uploadMetadata["filename"] = path.components(separatedBy: "/").last ?? path
    uploadMetadata["filetype"] = contentType

    let metadataString =
      uploadMetadata
      .map { "\($0.key) \(Data($0.value.utf8).base64EncodedString())" }
      .joined(separator: ",")

    var headers = HTTPFields()
    headers[.tusResumable] = Self.tusVersion
    headers[.uploadLength] = "\(contentLength)"
    headers[.uploadMetadata] = metadataString
    headers[.contentType] = "application/offset+octet-stream"

    if upsert {
      headers[.xUpsert] = "true"
    }

    let request = Helpers.HTTPRequest(
      url: storageApi.configuration.url.appendingPathComponent("upload/resumable/\(bucketId)"),
      method: .post,
      headers: headers
    )

    let response = try await storageApi.execute(request)

    guard let locationHeader = response.headers[.location],
      let uploadURL = URL(string: locationHeader)
    else {
      throw StorageError(
        statusCode: nil,
        message: "No location header in TUS upload creation response",
        error: nil
      )
    }

    let expiration = Date().addingTimeInterval(3600)  // 1 hour default
    let cacheEntry = ResumableCacheEntry(
      uploadURL: uploadURL.absoluteString,
      path: path,
      bucketId: bucketId,
      expiration: expiration,
      upsert: upsert,
      contentType: contentType
    )

    try await cache.set(fingerprint: fingerprint, entry: cacheEntry)
    return cacheEntry
  }

  func continueUpload(
    fingerprint: Fingerprint,
    cacheEntry: ResumableCacheEntry
  ) async throws -> ResumableCacheEntry? {
    guard cacheEntry.expiration > Date() else {
      try await cache.remove(fingerprint: fingerprint)
      return nil
    }

    guard let uploadURL = URL(string: cacheEntry.uploadURL) else {
      try await cache.remove(fingerprint: fingerprint)
      return nil
    }

    var headers = HTTPFields()
    headers[.tusResumable] = Self.tusVersion

    let request = Helpers.HTTPRequest(
      url: uploadURL,
      method: .head,
      headers: headers
    )

    do {
      _ = try await storageApi.execute(request)
      return cacheEntry
    } catch {
      try await cache.remove(fingerprint: fingerprint)
      return nil
    }
  }
}

extension HTTPField.Name {
  static let tusResumable = Self("tus-resumable")!
  static let uploadLength = Self("upload-length")!
  static let uploadOffset = Self("upload-offset")!
  static let uploadMetadata = Self("upload-metadata")!
  static let location = Self("location")!
  static let contentType = Self("content-type")!
}
