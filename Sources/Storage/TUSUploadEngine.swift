//
//  TUSUploadEngine.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package nonisolated(unsafe) var tusChunkSize = 6 * 1024 * 1024  // 6 MB — Supabase/S3 minimum

private struct TUSUploadServerResponse: Decodable {
  let Key: String
  let Id: UUID
}

enum UploadSource: Sendable {
  case data(Data)
  case fileURL(URL)

  func totalBytes() throws -> Int64 {
    switch self {
    case .data(let d):
      return Int64(d.count)
    case .fileURL(let url):
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let size = attrs[.size] as? Int64 else {
        throw StorageError(message: "Cannot determine file size", errorCode: .fileSystemError)
      }
      return size
    }
  }

  func readChunk(at offset: Int64, maxSize: Int) throws -> Data {
    switch self {
    case .data(let d):
      let start = Int(offset)
      let end = min(start + maxSize, d.count)
      return d[start..<end]
    case .fileURL(let url):
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(offset))
      return try handle.read(upToCount: maxSize) ?? Data()
    }
  }
}

actor TUSUploadEngine {
  enum State {
    case idle
    case creating
    case uploading(uploadURL: URL, offset: Int64)
    case paused(uploadURL: URL, offset: Int64)
    case completed(FileUploadResponse)
    case failed(StorageError)
    case cancelled
  }

  private let bucketId: String
  private let path: String
  private let source: UploadSource
  private let options: FileOptions
  private let client: StorageClient
  private let eventsContinuation: AsyncStream<TransferEvent<FileUploadResponse>>.Continuation
  private let resultContinuation: AsyncStream<Result<FileUploadResponse, any Error>>.Continuation

  private var state: State = .idle
  private var currentUploadTask: Task<Void, Never>?

  init(
    bucketId: String,
    path: String,
    source: UploadSource,
    options: FileOptions,
    client: StorageClient,
    eventsContinuation: AsyncStream<TransferEvent<FileUploadResponse>>.Continuation,
    resultContinuation: AsyncStream<Result<FileUploadResponse, any Error>>.Continuation
  ) {
    self.bucketId = bucketId
    self.path = path
    self.source = source
    self.options = options
    self.client = client
    self.eventsContinuation = eventsContinuation
    self.resultContinuation = resultContinuation
  }

  func start() {
    guard case .idle = state else { return }
    state = .creating
    currentUploadTask = Task { await run() }
  }

  func pause() {
    switch state {
    case .uploading(let url, let offset):
      currentUploadTask?.cancel()
      state = .paused(uploadURL: url, offset: offset)
    default:
      break
    }
  }

  func resume() {
    switch state {
    case .paused(let url, _):
      state = .creating  // prevent double-resume
      currentUploadTask = Task { await resumeFromServer(uploadURL: url) }
    default:
      break
    }
  }

  func cancel() {
    currentUploadTask?.cancel()
    state = .cancelled
    let error = StorageError.cancelled
    eventsContinuation.yield(.failed(error))
    eventsContinuation.finish()
    resultContinuation.yield(.failure(error))
    resultContinuation.finish()
  }

  // MARK: - Private

  private func run() async {
    do {
      try Task.checkCancellation()
      let totalBytes = try source.totalBytes()
      let uploadURL = try await createUpload(totalBytes: totalBytes)
      state = .uploading(uploadURL: uploadURL, offset: 0)
      try await uploadChunks(to: uploadURL, from: 0, totalBytes: totalBytes)
    } catch is CancellationError {
      switch state {
      case .cancelled, .paused:
        return
      default:
        cancel()
      }
    } catch let error as StorageError {
      finish(with: .failure(error))
    } catch {
      finish(with: .failure(StorageError.networkError(underlying: error)))
    }
  }

  private func resumeFromServer(uploadURL: URL) async {
    do {
      let serverOffset = try await fetchOffset(uploadURL: uploadURL)
      let totalBytes = try source.totalBytes()
      state = .uploading(uploadURL: uploadURL, offset: serverOffset)
      try await uploadChunks(to: uploadURL, from: serverOffset, totalBytes: totalBytes)
    } catch is CancellationError {
      switch state {
      case .cancelled, .paused:
        return
      default:
        cancel()
      }
    } catch let error as StorageError {
      finish(with: .failure(error))
    } catch {
      finish(with: .failure(StorageError.networkError(underlying: error)))
    }
  }

  private func finish(with result: Result<FileUploadResponse, any Error>) {
    switch result {
    case .success(let response):
      state = .completed(response)
      eventsContinuation.yield(.completed(response))
    case .failure(let error):
      let storageError = error as? StorageError ?? StorageError.networkError(underlying: error)
      state = .failed(storageError)
      eventsContinuation.yield(.failed(storageError))
    }
    eventsContinuation.finish()
    resultContinuation.yield(result.mapError { $0 })
    resultContinuation.finish()
  }

  // MARK: - TUS protocol

  private func createUpload(totalBytes: Int64) async throws -> URL {
    var request = makeRequest(
      url: client.url.appendingPathComponent("upload/resumable"),
      method: "POST"
    )
    request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
    request.setValue("\(totalBytes)", forHTTPHeaderField: "Upload-Length")
    request.setValue(tusMetadata(), forHTTPHeaderField: "Upload-Metadata")
    request.setValue("0", forHTTPHeaderField: "Content-Length")
    if options.upsert {
      request.setValue("true", forHTTPHeaderField: "x-upsert")
    }

    let (_, response) = try await client.http.session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StorageError(message: "Invalid response", errorCode: .unknown)
    }
    guard httpResponse.statusCode == 201,
      let location = httpResponse.value(forHTTPHeaderField: "Location"),
      let locationURL = URL(string: location)
    else {
      throw StorageError(
        message: "TUS create failed",
        errorCode: .unknown,
        statusCode: httpResponse.statusCode
      )
    }
    return locationURL
  }

  private func fetchOffset(uploadURL: URL) async throws -> Int64 {
    var request = makeRequest(url: uploadURL, method: "HEAD")
    request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")

    let (_, response) = try await client.http.session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      let offsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
      let offset = Int64(offsetString)
    else {
      throw StorageError(message: "TUS HEAD failed", errorCode: .unknown)
    }
    return offset
  }

  private func uploadChunks(to uploadURL: URL, from startOffset: Int64, totalBytes: Int64)
    async throws
  {
    var offset = startOffset
    while offset < totalBytes {
      try Task.checkCancellation()

      let chunk = try source.readChunk(at: offset, maxSize: tusChunkSize)
      guard !chunk.isEmpty else {
        throw StorageError(
          message: "Unexpected end of source data at offset \(offset)",
          errorCode: .fileSystemError
        )
      }

      var request = makeRequest(url: uploadURL, method: "PATCH")
      request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
      request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
      request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
      request.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")

      let (data, response) = try await client.http.session.upload(for: request, from: chunk)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw StorageError(message: "Invalid PATCH response", errorCode: .unknown)
      }

      if httpResponse.statusCode == 409 {
        let serverOffset = try await fetchOffset(uploadURL: uploadURL)
        offset = serverOffset
        continue
      }

      guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
        throw StorageError(
          message: "TUS PATCH failed",
          errorCode: .unknown,
          statusCode: httpResponse.statusCode
        )
      }

      guard
        let newOffsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
        let newOffset = Int64(newOffsetString)
      else {
        throw StorageError(message: "Missing Upload-Offset in PATCH response", errorCode: .unknown)
      }

      offset = newOffset

      eventsContinuation.yield(
        .progress(
          TransferProgress(
            bytesTransferred: offset,
            totalBytes: totalBytes
          )))

      if offset == totalBytes {
        let serverResponse = try JSONDecoder().decode(TUSUploadServerResponse.self, from: data)
        let uploadResponse = FileUploadResponse(
          id: serverResponse.Id,
          path: path,
          fullPath: serverResponse.Key
        )
        finish(with: .success(uploadResponse))
        return
      }

      state = .uploading(uploadURL: uploadURL, offset: offset)
    }
  }

  // MARK: - Helpers

  private func makeRequest(url: URL, method: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    for (key, value) in client.mergedHeaders([:]) {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return request
  }

  private func tusMetadata() -> String {
    let cleanPath = path.components(separatedBy: "/")
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    let contentType = options.contentType ?? "application/octet-stream"
    let cacheControl = options.cacheControl
    let entries: [(String, String)] = [
      ("bucketName", bucketId),
      ("objectName", cleanPath),
      ("contentType", contentType),
      ("cacheControl", cacheControl),
    ]
    return
      entries
      .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
      .joined(separator: ",")
  }
}

// MARK: - Factory

extension TUSUploadEngine {
  static func makeTask(
    bucketId: String,
    path: String,
    source: UploadSource,
    options: FileOptions,
    client: StorageClient
  ) -> StorageUploadTask {
    let (eventStream, eventsContinuation) =
      AsyncStream<TransferEvent<FileUploadResponse>>.makeStream()
    let (resultStream, resultContinuation) =
      AsyncStream<Result<FileUploadResponse, any Error>>.makeStream(
        bufferingPolicy: .bufferingNewest(1))

    let engine = TUSUploadEngine(
      bucketId: bucketId,
      path: path,
      source: source,
      options: options,
      client: client,
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )

    let resultTask = Task<FileUploadResponse, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    let task = StorageUploadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { Task { await engine.pause() } },
      resume: { Task { await engine.resume() } },
      cancel: { Task { await engine.cancel() } }
    )

    Task { await engine.start() }

    return task
  }
}
