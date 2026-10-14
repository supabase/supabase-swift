//
//  StorageRequests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes
import IssueReporting

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

  func listBuckets(_ options: BucketListOptions) -> StorageRequest {
    StorageRequest(head: HTTPRequest(method: .get, url: url("bucket", query: options.queryItems)))
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

  // MARK: - Analytics buckets

  func analyticsBuckets(_ options: BucketListOptions) -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .get, url: url("iceberg/bucket", query: options.queryItems)))
  }

  private struct AnalyticsBucketBody: Encodable {
    let name: String
  }

  func createAnalyticsBucket(_ name: String) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("iceberg/bucket")),
      body: try json(AnalyticsBucketBody(name: name)))
  }

  func deleteAnalyticsBucket(_ name: String) -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .delete, url: url("iceberg/bucket/\(ObjectKey.encode(name))")))
  }

  // MARK: - Objects

  /// `POST` creates, `PUT` replaces. The file travels as the raw body, the same shape
  /// supabase-js uses for `ArrayBuffer` uploads; what a multipart form would carry as fields
  /// travels in headers: `Content-Type`, `Cache-Control`, and base64 JSON in `x-metadata`.
  func upload(
    method: HTTPRequest.Method, bucket: String, key: ObjectKey, body: HTTPBody,
    options: UploadOptions
  ) throws -> StorageRequest {
    var headers = try uploadHeaders(key: key, options: options)
    if method == .post {
      headers[.xUpsert] = "\(options.upsert)"
    } else if options.upsert {
      reportIssue(
        "UploadOptions.upsert has no effect on update(path:): PUT always replaces the object.")
    }
    return StorageRequest(
      head: HTTPRequest(
        method: method, url: url("object/\(objectPath(bucket, key))"), headerFields: headers),
      body: body)
  }

  /// Upsert is decided by the token, so `options.upsert` is not sent.
  func uploadToSignedURL(
    bucket: String, key: ObjectKey, token: String, body: HTTPBody, options: UploadOptions
  ) throws -> StorageRequest {
    let headers = try uploadHeaders(key: key, options: options)
    return StorageRequest(
      head: HTTPRequest(
        method: .put,
        url: url(
          "object/upload/sign/\(objectPath(bucket, key))",
          query: [URLQueryItem(name: "token", value: token)]),
        headerFields: headers),
      body: body)
  }

  private func uploadHeaders(key: ObjectKey, options: UploadOptions) throws
    -> HTTPFields
  {
    var headers = options.headers
    if headers[.contentType] == nil {
      headers[.contentType] =
        options.contentType ?? mimeType(forPathExtension: key.path.pathExtension)
    }
    if headers[.cacheControl] == nil {
      headers[.cacheControl] = options.cacheControl.rawValue
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
    struct Metadata: Encodable {
      let cacheControl: String?
      let mimetype: String?
    }

    let bucketId: String
    let sourceKey: String
    let destinationKey: String
    let destinationBucket: String?
    let sourceVersionId: String?
    var copyMetadata: Bool?
    var metadata: Metadata?
  }

  func move(
    bucket: String, source: ObjectKey, destination: ObjectKey, destinationBucket: String?,
    sourceVersionId: String?
  ) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/move")),
      body: try json(
        MoveOrCopyBody(
          bucketId: bucket, sourceKey: source.path, destinationKey: destination.path,
          destinationBucket: destinationBucket, sourceVersionId: sourceVersionId)))
  }

  /// User metadata and upsert travel in headers, as on upload; the system metadata override in
  /// the body.
  func copy(
    bucket: String, source: ObjectKey, destination: ObjectKey, destinationBucket: String?,
    sourceVersionId: String?, options: CopyOptions
  ) throws -> StorageRequest {
    var body = MoveOrCopyBody(
      bucketId: bucket, sourceKey: source.path, destinationKey: destination.path,
      destinationBucket: destinationBucket, sourceVersionId: sourceVersionId)
    if !options.copyMetadata {
      body.copyMetadata = false
    }
    if options.cacheControl != nil || options.contentType != nil {
      body.metadata = MoveOrCopyBody.Metadata(
        cacheControl: options.cacheControl?.rawValue, mimetype: options.contentType)
    }
    var headers = HTTPFields()
    if options.upsert {
      headers[.xUpsert] = "true"
    }
    if let metadata = options.metadata {
      headers[.xMetadata] = try encodeMetadata(metadata)
    }
    return StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/copy"), headerFields: headers),
      body: try json(body))
  }

  private struct SignBody: Encodable {
    let expiresIn: Int
    let transform: ImageTransform.Body?
    let versionId: String?
  }

  func sign(
    bucket: String, key: ObjectKey, expiresIn: Int, transform: ImageTransform?, versionId: String?
  ) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/sign/\(objectPath(bucket, key))")),
      body: try json(
        SignBody(expiresIn: expiresIn, transform: transform?.body, versionId: versionId)))
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

  private struct RemoveBody<Prefix: Encodable>: Encodable {
    let prefixes: [Prefix]
  }

  private struct VersionPrefix: Encodable {
    let path: String
    let versionId: String
  }

  func remove(bucket: String, keys: [ObjectKey]) throws -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(method: .delete, url: url("object/\(ObjectKey.encode(bucket))")),
      body: try json(RemoveBody(prefixes: keys.map(\.path))))
  }

  func remove(bucket: String, versions: [(key: ObjectKey, versionId: String)]) throws
    -> StorageRequest
  {
    StorageRequest(
      head: HTTPRequest(method: .delete, url: url("object/\(ObjectKey.encode(bucket))")),
      body: try json(
        RemoveBody(
          prefixes: versions.map { VersionPrefix(path: $0.key.path, versionId: $0.versionId) })))
  }

  private struct SortBody: Encodable {
    let column: String
    let order: SortOrder
  }

  private struct ListBody: Encodable {
    let prefix: String
    let limit: Int
    let offset: Int
    let sortBy: SortBody
    let search: String?
    let exactMatch: Bool?
    let noncurrentVersions: String?
    let deleteMarkers: String?
  }

  /// Sends the server defaults for the fields the caller left `nil`, so a sort column without an
  /// order (or the reverse) keeps the other half.
  func list(bucket: String, prefix: ObjectKey, options: ListOptions) throws -> StorageRequest {
    let body = ListBody(
      prefix: prefix.path,
      limit: options.limit ?? 100,
      offset: options.offset ?? 0,
      sortBy: SortBody(
        column: (options.sortBy ?? .name).rawValue, order: options.order ?? .ascending),
      search: options.search,
      exactMatch: options.exactMatch,
      noncurrentVersions: options.versions?.rawValue,
      deleteMarkers: options.deleteMarkers?.rawValue)
    return StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/list/\(ObjectKey.encode(bucket))")),
      body: try json(body), replayable: true)
  }

  private struct ListV2Body: Encodable {
    let prefix: String
    let limit: Int?
    let cursor: String?
    let withDelimiter: Bool
    let sortBy: SortBody?
    let exactMatch: Bool?
    let noncurrentVersions: String?
    let deleteMarkers: String?

    enum CodingKeys: String, CodingKey {
      case prefix, limit, cursor, sortBy, exactMatch, noncurrentVersions, deleteMarkers
      case withDelimiter = "with_delimiter"
    }
  }

  /// The cursor locks the sort and filters server-side, so every page sends the same options.
  func objects(bucket: String, prefix: ListPrefix, options: ObjectListingOptions, cursor: String?)
    throws -> StorageRequest
  {
    let sortBy =
      options.sortBy == nil && options.order == nil
      ? nil
      : SortBody(
        column: (options.sortBy ?? .name).rawValue, order: options.order ?? .ascending)
    let body = ListV2Body(
      prefix: prefix.path,
      limit: options.pageSize,
      cursor: cursor,
      withDelimiter: options.delimited,
      sortBy: sortBy,
      exactMatch: options.exactMatch,
      noncurrentVersions: options.versions?.rawValue,
      deleteMarkers: options.deleteMarkers?.rawValue)
    return StorageRequest(
      head: HTTPRequest(method: .post, url: url("object/list-v2/\(ObjectKey.encode(bucket))")),
      body: try json(body), replayable: true)
  }

  /// A transform routes to `render/image/authenticated`; the plain object route otherwise.
  func download(
    bucket: String, key: ObjectKey, transform: ImageTransform?, options: DownloadOptions
  ) -> StorageRequest {
    let transform = transform?.queryItems ?? []
    let route = transform.isEmpty ? "object" : "render/image/authenticated"
    var query = transform
    if let versionId = options.versionId {
      query.append(URLQueryItem(name: "versionId", value: versionId))
    }
    if let cacheNonce = options.cacheNonce {
      query.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
    }
    var headers = HTTPFields()
    if let range = options.range {
      headers[.range] = "bytes=\(range.lowerBound)-\(range.upperBound)"
    }
    return StorageRequest(
      head: HTTPRequest(
        method: .get, url: url("\(route)/\(objectPath(bucket, key))", query: query),
        headerFields: headers.merging(with: options.headers)))
  }

  func info(bucket: String, key: ObjectKey, versionId: String?) -> StorageRequest {
    StorageRequest(
      head: HTTPRequest(
        method: .get,
        url: url(
          "object/info/\(objectPath(bucket, key))",
          query: versionId.map { [URLQueryItem(name: "versionId", value: $0)] } ?? [])))
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
  static let xMetadata = Self("x-metadata")!
  static let xUpsert = Self("x-upsert")!
}
