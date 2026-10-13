//
//  StorageRequests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// One request to send: the head, an optional body, and whether a non-idempotent method is still
/// safe to replay (a list is a `POST` that only reads).
struct StorageRequest: Sendable {
  var head: HTTPRequest
  var body: HTTPBody?
  var replayable = false
}

/// Builds the request for each Storage route, so every URL, header and body is spelled in one
/// place. Object paths arrive as ``ObjectKey`` values; bucket ids are encoded here for the one
/// segment they occupy.
struct StorageRequests: Sendable {
  private let base: URLComponents

  /// The base URL every route is appended to.
  let url: URL

  init(url: URL) {
    // `url` is supplied once, at construction, so a URL that cannot be decomposed is a programmer
    // error, not a runtime condition. Trap here, where the offending value is, rather than letting
    // it fail later as an opaque `URLError`.
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      preconditionFailure("Storage client initialized with an invalid URL: \(url)")
    }
    while components.percentEncodedPath.hasSuffix("/") {
      components.percentEncodedPath.removeLast()
    }
    self.base = components
    self.url = url
  }

  /// The URL for `encodedPath` under the base, with `query` appended.
  func url(_ encodedPath: String, query: [URLQueryItem] = []) -> URL {
    var components = base
    components.percentEncodedPath += "/\(encodedPath)"
    guard let url = components.url else {
      // The base was validated at construction and every segment is percent-encoded by
      // `ObjectKey`, so the components always form a URL. Reaching this is an SDK bug.
      preconditionFailure("Storage built an invalid URL from \(components)")
    }
    return url.appendingQueryItems(query)
  }

  /// Resolves a URL the server returned relative to its own root, such as a signed URL, against
  /// the base, with `query` appended.
  func resolve(_ relative: String, query: [URLQueryItem] = []) throws -> URL {
    guard let relativeComponents = URLComponents(string: relative) else {
      throw StorageError(kind: .decoding, message: "Cannot build a signed URL from '\(relative)'.")
    }
    var components = base
    let path = relativeComponents.percentEncodedPath
    components.percentEncodedPath += path.hasPrefix("/") ? path : "/\(path)"
    components.percentEncodedQueryItems = relativeComponents.percentEncodedQueryItems
    guard let url = components.url else {
      throw StorageError(kind: .decoding, message: "Cannot build a signed URL from '\(relative)'.")
    }
    return url.appendingQueryItems(query)
  }

  private func json(_ value: some Encodable) throws -> HTTPBody {
    do {
      return HTTPBody(try JSONEncoder.storage.encode(value))
    } catch {
      throw StorageError(
        kind: .invalidRequest, message: "The request body cannot be encoded as JSON.",
        underlyingError: error)
    }
  }

  private func objectPath(_ bucket: String, _ key: ObjectKey) -> String {
    "\(ObjectKey.encode(bucket))/\(key.encoded)"
  }

  // MARK: - Buckets

  func listBuckets() -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .get, url: url("bucket")))
  }

  func bucket(_ id: String) -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .get, url: url("bucket/\(ObjectKey.encode(id))")))
  }

  func createBucket(_ parameters: some Encodable) throws -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .post, url: url("bucket")), body: try json(parameters))
  }

  func updateBucket(_ id: String, _ parameters: some Encodable) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .put, url: url("bucket/\(ObjectKey.encode(id))")),
      body: try json(parameters))
  }

  func emptyBucket(_ id: String) -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("bucket/\(ObjectKey.encode(id))/empty")))
  }

  func deleteBucket(_ id: String) -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .delete, url: url("bucket/\(ObjectKey.encode(id))")))
  }

  /// `DELETE cdn/{bucket}` purges the bucket; with `key`, one object.
  func purgeCache(bucket: String, key: ObjectKey?, transformationsOnly: Bool) -> StorageRequest {
    let path = key.map { objectPath(bucket, $0) } ?? ObjectKey.encode(bucket)
    return StorageRequest(
      head: HTTPRequest(
        method: .delete,
        url: url(
          "cdn/\(path)",
          query: transformationsOnly ? [URLQueryItem(name: "transformations", value: "true")] : [])
      ))
  }

  // MARK: - Objects

  /// `POST` creates, `PUT` replaces. The file travels as the raw body, the same shape
  /// supabase-js uses for `ArrayBuffer` uploads; what a multipart form would carry as fields
  /// travels in headers: `Content-Type`, `Cache-Control`, and base64 JSON in `x-metadata`.
  func upload(
    method: HTTPRequest.Method, bucket: String, key: ObjectKey, file: FileUpload,
    options: FileOptions
  ) throws -> StorageRequest {
    var headers = try uploadHeaders(file: file, key: key, options: options)
    if method == .post {
      headers[.xUpsert] = "\(options.shouldUpsert)"
    }
    return StorageRequest(
      head: HTTPRequest(
        method: method, url: url("object/\(objectPath(bucket, key))"), headerFields: headers),
      body: try file.httpBody())
  }

  func uploadToSignedURL(
    bucket: String, key: ObjectKey, token: String, file: FileUpload, options: FileOptions
  ) throws -> StorageRequest {
    var headers = try uploadHeaders(file: file, key: key, options: options)
    headers[.xUpsert] = "\(options.shouldUpsert)"
    return StorageRequest(
      head: HTTPRequest(
        method: .put,
        url: url(
          "object/upload/sign/\(objectPath(bucket, key))",
          query: [URLQueryItem(name: "token", value: token)]),
        headerFields: headers),
      body: try file.httpBody())
  }

  private func uploadHeaders(file: FileUpload, key: ObjectKey, options: FileOptions) throws
    -> HTTPFields
  {
    var headers = options.headers.map { HTTPFields($0) } ?? HTTPFields()
    headers[.duplex] = options.duplex
    if headers[.contentType] == nil {
      headers[.contentType] = file.contentType(forPath: key.path, options: options)
    }
    if headers[.cacheControl] == nil {
      headers[.cacheControl] = "max-age=\(options.cacheControl)"
    }
    if let metadata = options.metadata {
      headers[.xMetadata] = try encodeMetadata(metadata)
    }
    return headers
  }

  func createSignedUploadURL(bucket: String, key: ObjectKey, upsert: Bool) -> StorageRequest {
    var headers = HTTPFields()
    if upsert {
      headers[.xUpsert] = "true"
    }
    return StorageRequest(
      head: HTTPRequest(
        method: .post, url: url("object/upload/sign/\(objectPath(bucket, key))"),
        headerFields: headers))
  }

  private struct MoveOrCopyBody: Encodable {
    let bucketId: String
    let sourceKey: String
    let destinationKey: String
    let destinationBucket: String?
  }

  func move(bucket: String, source: ObjectKey, destination: ObjectKey, destinationBucket: String?)
    throws -> StorageRequest
  {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/move")),
      body: try json(
        MoveOrCopyBody(
          bucketId: bucket, sourceKey: source.path, destinationKey: destination.path,
          destinationBucket: destinationBucket)))
  }

  func copy(bucket: String, source: ObjectKey, destination: ObjectKey, destinationBucket: String?)
    throws -> StorageRequest
  {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/copy")),
      body: try json(
        MoveOrCopyBody(
          bucketId: bucket, sourceKey: source.path, destinationKey: destination.path,
          destinationBucket: destinationBucket)))
  }

  private struct SignBody: Encodable {
    let expiresIn: Int
    let transform: TransformOptions?
  }

  func sign(bucket: String, key: ObjectKey, expiresIn: Int, transform: TransformOptions?) throws
    -> StorageRequest
  {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/sign/\(objectPath(bucket, key))")),
      body: try json(SignBody(expiresIn: expiresIn, transform: transform)))
  }

  private struct SignManyBody: Encodable {
    let expiresIn: Int
    let paths: [String]
  }

  func sign(bucket: String, keys: [ObjectKey], expiresIn: Int) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/sign/\(ObjectKey.encode(bucket))")),
      body: try json(SignManyBody(expiresIn: expiresIn, paths: keys.map(\.path))))
  }

  private struct RemoveBody: Encodable {
    let prefixes: [String]
  }

  func remove(bucket: String, keys: [ObjectKey]) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .delete, url: url("object/\(ObjectKey.encode(bucket))")),
      body: try json(RemoveBody(prefixes: keys.map(\.path))))
  }

  private static let defaultSearchOptions = SearchOptions(
    limit: 100, offset: 0, sortBy: SortBy(column: "name", order: .ascending))

  /// Fills in the server defaults the caller left `nil`, so a partial `SortBy` keeps the other
  /// half instead of dropping it.
  func list(bucket: String, prefix: ObjectKey, options: SearchOptions?) throws -> StorageRequest {
    let defaults = Self.defaultSearchOptions
    var options = options ?? defaults
    options.limit = options.limit ?? defaults.limit
    options.offset = options.offset ?? defaults.offset
    options.prefix = prefix.path
    var sortBy = options.sortBy ?? SortBy()
    sortBy.column = sortBy.column ?? defaults.sortBy?.column
    sortBy.order = sortBy.order ?? defaults.sortBy?.order
    options.sortBy = sortBy

    return StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/list/\(ObjectKey.encode(bucket))")),
      body: try json(options), replayable: true)
  }

  /// A transform routes to `render/image/authenticated`; the plain object route otherwise.
  func download(bucket: String, key: ObjectKey, transform: [URLQueryItem], query: [URLQueryItem])
    -> StorageRequest
  {
    let route = transform.isEmpty ? "object" : "render/image/authenticated"
    return StorageRequest(
      head: HTTPRequest(
        method: .get, url: url("\(route)/\(objectPath(bucket, key))", query: transform + query)))
  }

  func info(bucket: String, key: ObjectKey) -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .get, url: url("object/info/\(objectPath(bucket, key))")))
  }

  func exists(bucket: String, key: ObjectKey) -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .head, url: url("object/\(objectPath(bucket, key))")))
  }

  /// A transform routes to `render/image/public`; the plain public object route otherwise.
  func publicURL(bucket: String, key: ObjectKey, transform: [URLQueryItem], query: [URLQueryItem])
    -> URL
  {
    let route = transform.isEmpty ? "object" : "render/image"
    return url("\(route)/public/\(objectPath(bucket, key))", query: query + transform)
  }
}

/// The body Storage returns for an upload, a signed-URL upload and a copy: the full key, and
/// the object id except after a signed-URL upload.
struct UploadResponse: Decodable {
  let key: String
  let id: String?

  enum CodingKeys: String, CodingKey {
    case key = "Key"
    case id = "Id"
  }
}

extension HTTPField.Name {
  static let duplex = Self("duplex")!
  static let xMetadata = Self("x-metadata")!
  static let xUpsert = Self("x-upsert")!
}
