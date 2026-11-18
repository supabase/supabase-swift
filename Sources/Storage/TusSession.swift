//
//  TusSession.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import Foundation
import Helpers
import HTTPTypes

/// Speaks tus 1.0 to `upload/resumable` through the shared `HTTPClient`, so the access token,
/// logging and user middlewares apply to every chunk.
///
/// Metadata encoding is the only inference it makes; it never decodes the body of a response
/// beyond the one the final `PATCH` returns. The upload URL is the path and query of the
/// `Location` the server sent, on the origin of the tus endpoint, and no request goes to an
/// upload URL off that origin (see ``StorageRequests/tusUploadURL(location:)``).
struct TusSession: Sendable {
  struct Created: Hashable, Sendable {
    var uploadURL: URL
    var offset: Int64
    var expiresAt: Date?
  }

  struct Appended: Hashable, Sendable {
    var offset: Int64
    var complete: Bool
    var body: Data
  }

  /// A server answer the upload loop has to react to rather than report.
  enum Failure: Error {
    /// `409` on `PATCH`: most often the server's offset is not the one sent. Ask for it with
    /// ``TusSession/offset(of:)`` and continue from there. Storage also refuses with `409` for
    /// other reasons, so a resync that finds the offset unchanged fails with this error.
    case offsetConflict(StorageError)
    /// `404` or `410`: the upload no longer exists on the server. Create it again.
    case uploadGone(StorageError)
  }

  let api: StorageAPI
  let options: UploadOptions

  func create(
    bucket: String, key: ObjectKey, length: Int64, firstChunk: Data? = nil
  ) async throws -> Created {
    let request = try api.requests.tusCreate(
      bucket: bucket, key: key, length: length, options: options, firstChunk: firstChunk)
    let (head, body) = try await api.stream(request)
    try await drain(body)

    guard let location = head.headerFields[.location],
      let resolved = URL(string: location, relativeTo: request.head.url)?.absoluteURL
    else {
      throw StorageError(
        kind: .server, message: "The resumable upload was created without a Location.",
        response: HTTPErrorResponse(head, body: Data()))
    }
    guard let uploadURL = api.requests.tusUploadURL(location: resolved) else {
      throw StorageError(
        kind: .server,
        message: "The resumable upload was created with a Location outside upload/resumable.",
        response: HTTPErrorResponse(head, body: Data()))
    }
    // Plain creation (no body) answers without Upload-Offset; creation-with-upload must carry it.
    return Created(
      uploadURL: uploadURL,
      offset: firstChunk == nil && head.headerFields[.uploadOffset] == nil
        ? 0 : try uploadOffset(of: head),
      expiresAt: head.headerFields[.uploadExpires].flatMap(DownloadResponse.httpDate))
  }

  func offset(of uploadURL: URL) async throws -> Int64 {
    try check(uploadURL)
    let (head, body) = try await send(
      api.requests.tusOffset(of: uploadURL, upsert: options.upsert), conflictIsOffset: false)
    try await drain(body)
    return try uploadOffset(of: head)
  }

  func append(_ chunk: HTTPBody, at offset: Int64, to uploadURL: URL) async throws -> Appended {
    try check(uploadURL)
    let (head, body) = try await send(
      api.requests.tusAppend(chunk, at: offset, to: uploadURL, upsert: options.upsert),
      conflictIsOffset: true)
    let data = if let body { try await Data(collecting: body, upTo: .max) } else { Data() }
    return Appended(
      offset: try uploadOffset(of: head),
      complete: head.headerFields[.tusComplete] == "1",
      body: data)
  }

  /// Best effort: a failure here leaves an upload the server expires on its own.
  func terminate(_ uploadURL: URL) async {
    guard api.requests.isTusUploadURL(uploadURL) else { return }
    _ = try? await api.execute(api.requests.tusTerminate(uploadURL, upsert: options.upsert))
  }

  /// Throws unless `uploadURL` is an upload under the tus endpoint, on its origin, so a record
  /// edited on disk cannot send the access token to another host.
  func check(_ uploadURL: URL) throws {
    guard api.requests.isTusUploadURL(uploadURL) else {
      throw StorageError(
        kind: .server,
        message: "The resumable upload URL is not an upload under this storage endpoint.")
    }
  }

  private func send(_ request: StorageRequest, conflictIsOffset: Bool) async throws
    -> (HTTPResponse, HTTPBody?)
  {
    do {
      return try await api.stream(request)
    } catch let error as StorageError {
      switch error.serverError?.statusCode {
      case 404, 410: throw Failure.uploadGone(error)
      case 409 where conflictIsOffset: throw Failure.offsetConflict(error)
      default: throw error
      }
    }
  }

  private func uploadOffset(of head: HTTPResponse) throws -> Int64 {
    guard let offset = head.headerFields[.uploadOffset].flatMap({ Int64($0) }) else {
      throw StorageError(
        kind: .server, message: "The resumable upload response has no Upload-Offset.",
        response: HTTPErrorResponse(head, body: Data()))
    }
    return offset
  }

  private func drain(_ body: HTTPBody?) async throws {
    guard let body else { return }
    for try await _ in body {}
  }
}
