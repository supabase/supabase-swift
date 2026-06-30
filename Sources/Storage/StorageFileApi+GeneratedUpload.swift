//
//  StorageFileApi+GeneratedUpload.swift
//  Storage
//
//  SPIKE — demonstrates how the generated multipart client handles streaming
//  uploads. The file part is backed by an AsyncStream of 64 KB chunks from
//  FileHandle, so the file is never fully buffered in memory.
//
//  TUS (resumable) uploads are NOT covered here — the TUS state machine
//  cannot be expressed in standard OpenAPI and stays hand-written.
//
//  Content-Type limitation: the generated serializer hardcodes
//  "application/octet-stream" for the file part. Passing a custom MIME type
//  requires a raw MultipartRawPart, which is left as a follow-up.
//

import Foundation
import OpenAPIRuntime

extension StorageFileAPI {

  // MARK: - Upload (POST) via generated client

  /// Upload `data` to `path` using the generated multipart client.
  func uploadViaGeneratedClient(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions(),
    upsert: Bool = false
  ) async throws -> FileUploadedResponse {
    let (bucketId, objectPath) = splitPath(path)
    typealias Part = Operations.UploadObject.Input.Body.multipartFormPayload

    var parts: [Part] = [
      .cacheControl(.init(payload: .init(body: HTTPBody(options.cacheControl)), filename: nil))
    ]
    if let metadata = options.metadata,
      let container = try? OpenAPIObjectContainer(unvalidatedValue: metadata)
    {
      parts.append(
        .metadata(
          .init(payload: .init(body: .init(additionalProperties: container)), filename: nil)))
    }
    parts.append(.file(.init(payload: .init(body: HTTPBody(data)), filename: nil)))

    let output = try await client.generatedClient.UploadObject(
      path: .init(bucketId: bucketId, wildcardPath_plus_: objectPath),
      headers: .init(x_hyphen_upsert: upsert ? "true" : nil),
      body: .multipartForm(MultipartBody(parts))
    )
    switch output {
    case .ok(let ok):
      switch ok.body {
      case .json(let body): return FileUploadedResponse(key: body.Key, id: body.Id)
      }
    case .badRequest(let err):
      switch err.body {
      case .json(let body):
        throw URLError(
          .unknown, userInfo: [NSLocalizedDescriptionKey: body.message ?? "Unknown error"])
      }
    case .undocumented(let code, _):
      throw URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
    }
  }

  /// Upload a file at `fileURL` streaming in 64 KB chunks.
  func uploadViaGeneratedClient(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions(),
    upsert: Bool = false
  ) async throws -> FileUploadedResponse {
    let (bucketId, objectPath) = splitPath(path)
    typealias Part = Operations.UploadObject.Input.Body.multipartFormPayload

    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap {
      Int64($0)
    }
    let length: HTTPBody.Length = fileSize.map { .known($0) } ?? .unknown
    let fileBody = chunkedBody(from: fileURL, length: length)

    var parts: [Part] = [
      .cacheControl(.init(payload: .init(body: HTTPBody(options.cacheControl)), filename: nil))
    ]
    if let metadata = options.metadata,
      let container = try? OpenAPIObjectContainer(unvalidatedValue: metadata)
    {
      parts.append(
        .metadata(
          .init(payload: .init(body: .init(additionalProperties: container)), filename: nil)))
    }
    parts.append(.file(.init(payload: .init(body: fileBody), filename: nil)))

    let output = try await client.generatedClient.UploadObject(
      path: .init(bucketId: bucketId, wildcardPath_plus_: objectPath),
      headers: .init(x_hyphen_upsert: upsert ? "true" : nil),
      body: .multipartForm(MultipartBody(parts))
    )
    switch output {
    case .ok(let ok):
      switch ok.body {
      case .json(let body): return FileUploadedResponse(key: body.Key, id: body.Id)
      }
    case .badRequest(let err):
      switch err.body {
      case .json(let body):
        throw URLError(
          .unknown, userInfo: [NSLocalizedDescriptionKey: body.message ?? "Unknown error"])
      }
    case .undocumented(let code, _):
      throw URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
    }
  }

  // MARK: - Update (PUT) via generated client

  /// Overwrite the object at `path` using the generated multipart client.
  func updateViaGeneratedClient(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
  ) async throws -> FileUploadedResponse {
    let (bucketId, objectPath) = splitPath(path)
    typealias Part = Operations.UpdateObject.Input.Body.multipartFormPayload

    var parts: [Part] = [
      .cacheControl(.init(payload: .init(body: HTTPBody(options.cacheControl)), filename: nil))
    ]
    if let metadata = options.metadata,
      let container = try? OpenAPIObjectContainer(unvalidatedValue: metadata)
    {
      parts.append(
        .metadata(
          .init(payload: .init(body: .init(additionalProperties: container)), filename: nil)))
    }
    parts.append(.file(.init(payload: .init(body: HTTPBody(data)), filename: nil)))

    let output = try await client.generatedClient.UpdateObject(
      path: .init(bucketId: bucketId, wildcardPath_plus_: objectPath),
      body: .multipartForm(MultipartBody(parts))
    )
    switch output {
    case .ok(let ok):
      switch ok.body {
      case .json(let body): return FileUploadedResponse(key: body.Key, id: body.Id)
      }
    case .badRequest(let err):
      switch err.body {
      case .json(let body):
        throw URLError(
          .unknown, userInfo: [NSLocalizedDescriptionKey: body.message ?? "Unknown error"])
      }
    case .undocumented(let code, _):
      throw URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
    }
  }

  // MARK: - Private helpers

  private func splitPath(_ path: String) -> (bucketId: String, objectPath: String) {
    let components = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    return (
      components.first.map(String.init) ?? "",
      components.dropFirst().first.map(String.init) ?? ""
    )
  }

  /// Wraps a file URL in an HTTPBody that streams 64 KB chunks via FileHandle.
  private func chunkedBody(from url: URL, length: HTTPBody.Length) -> HTTPBody {
    let chunkSize = 65_536
    return HTTPBody(
      AsyncStream<ArraySlice<UInt8>> { continuation in
        Task {
          guard let handle = try? FileHandle(forReadingFrom: url) else {
            continuation.finish()
            return
          }
          defer { try? handle.close() }
          while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            continuation.yield(ArraySlice(chunk))
          }
          continuation.finish()
        }
      },
      length: length,
      iterationBehavior: .single
    )
  }
}

/// Return value from upload/update operations.
public struct FileUploadedResponse: Sendable {
  public let key: String
  public let id: String?
}
