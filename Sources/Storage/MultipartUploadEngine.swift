//
//  MultipartUploadEngine.swift
//  Storage
//

import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private struct MultipartServerResponse: Decodable {
  let Key: String
  let Id: UUID
}

actor MultipartUploadEngine {
  enum State {
    case idle
    case uploading
    case completed(FileUploadResponse)
    case failed(StorageError)
    case cancelled

    var isTerminal: Bool {
      switch self {
      case .completed, .failed, .cancelled: return true
      default: return false
      }
    }
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
    state = .uploading
    currentUploadTask = Task { await run() }
  }

  // Multipart uploads do not support pause/resume — the single-shot request cannot be
  // interrupted and resumed mid-flight. These are intentional no-ops; callers that need
  // pause/resume should use the TUS upload path instead.
  func pause() {}
  func resume() {}

  func cancel() {
    guard !state.isTerminal else { return }
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
      let response = try await performUpload()
      finish(with: .success(response))
    } catch {
      handleError(error)
    }
  }

  private func performUpload() async throws -> FileUploadResponse {
    #if DEBUG
      let builder = MultipartBuilder(
        boundary: testingBoundary.value ?? "----sb-\(UUID().uuidString)"
      )
    #else
      let builder = MultipartBuilder()
    #endif

    let multipart = source.append(to: builder, withPath: path, options: options)

    var headers: [String: String] = [:]
    headers["Content-Type"] = multipart.contentType
    if options.upsert {
      headers["x-upsert"] = "true"
    }

    var url = client.url.appendingPathComponent("object").appendingPathComponent(bucketId)
    for component in path.split(separator: "/") {
      url = url.appendingPathComponent(String(component))
    }

    let request = try await client.http.createRequest(
      .post,
      url: url,
      headers: client.mergedHeaders(headers)
    )

    do {
      let (data, urlResponse) = try await uploadWithProgress(request: request, multipart: multipart)
      let httpResponse = try client.http.validateResponse(urlResponse, data: data)
      client.logResponse(httpResponse, data: data)
      let serverResponse = try client.decoder.decode(MultipartServerResponse.self, from: data)
      return FileUploadResponse(id: serverResponse.Id, path: path, fullPath: serverResponse.Key)
    } catch {
      client.logFailure(error)
      throw client.translateStorageError(error)
    }
  }

  private func uploadWithProgress(
    request: URLRequest,
    multipart: MultipartBuilder
  ) async throws -> (Data, URLResponse) {
    let progressContinuation = eventsContinuation

    let progressDelegate = UploadProgressDelegate { sent, total in
      progressContinuation.yield(
        .progress(TransferProgress(bytesTransferred: sent, totalBytes: total))
      )
    }

    if try source.usesTempFileUpload {
      let tempFile = try multipart.buildToTempFile()
      defer { try? FileManager.default.removeItem(at: tempFile) }
      #if canImport(Darwin)
        return try await client.http.session.upload(
          for: request, fromFile: tempFile, delegate: progressDelegate)
      #else
        let result = try await client.http.session.upload(for: request, fromFile: tempFile)
        let totalBytes = (try? source.totalBytes()) ?? 0
        progressContinuation.yield(
          .progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        )
        return result
      #endif
    } else {
      let body = try multipart.buildInMemory()
      #if canImport(Darwin)
        return try await client.http.session.upload(
          for: request, from: body, delegate: progressDelegate)
      #else
        let result = try await client.http.session.upload(for: request, from: body)
        let totalBytes = Int64(body.count)
        progressContinuation.yield(
          .progress(TransferProgress(bytesTransferred: totalBytes, totalBytes: totalBytes))
        )
        return result
      #endif
    }
  }

  private func handleError(_ error: any Error) {
    let isCancellation =
      error is CancellationError || (error as? URLError)?.code == .cancelled
    if isCancellation {
      switch state {
      case .uploading:
        cancel()
      default:
        return
      }
    } else {
      finish(with: .failure(StorageError.from(error)))
    }
  }

  private func finish(with result: Result<FileUploadResponse, any Error>) {
    switch result {
    case .success(let response):
      state = .completed(response)
      eventsContinuation.yield(.completed(response))
    case .failure(let error):
      let storageError =
        error as? StorageError ?? StorageError.networkError(underlying: error)
      state = .failed(storageError)
      eventsContinuation.yield(.failed(storageError))
    }
    eventsContinuation.finish()
    resultContinuation.yield(result.mapError { $0 })
    resultContinuation.finish()
  }
}

// MARK: - Factory

extension MultipartUploadEngine {
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

    let engine = MultipartUploadEngine(
      bucketId: bucketId,
      path: path,
      source: source,
      options: options,
      client: client,
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )

    eventsContinuation.onTermination = { reason in
      guard case .cancelled = reason else { return }
      Task { await engine.cancel() }
    }

    let resultTask = Task<FileUploadResponse, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    let task = StorageUploadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { await engine.pause() },
      resume: { await engine.resume() },
      cancel: { await engine.cancel() }
    )

    Task { await engine.start() }

    return task
  }
}

// MARK: - Progress delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  let handler: @Sendable (Int64, Int64) -> Void

  init(handler: @Sendable @escaping (Int64, Int64) -> Void) {
    self.handler = handler
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    handler(totalBytesSent, totalBytesExpectedToSend)
  }
}
