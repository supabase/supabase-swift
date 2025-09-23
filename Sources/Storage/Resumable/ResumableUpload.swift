import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct ResumableUploadOptions: Sendable {
  public let chunkSize: Int64
  public let retryLimit: Int
  public let retryDelay: TimeInterval

  public init(
    chunkSize: Int64 = 6 * 1024 * 1024,
    retryLimit: Int = 3,
    retryDelay: TimeInterval = 1.0
  ) {
    self.chunkSize = chunkSize
    self.retryLimit = retryLimit
    self.retryDelay = retryDelay
  }
}

public actor ResumableUpload {
  public let state: AsyncStream<ResumableUploadState>

  private let fingerprint: Fingerprint
  private let data: Data
  private let client: any ResumableClient
  private let storageApi: StorageApi
  private let options: ResumableUploadOptions
  private let stateContinuation: AsyncStream<ResumableUploadState>.Continuation

  private var isPaused = false
  private var isCancelled = false
  private var currentOffset: Int64 = 0

  init(
    fingerprint: Fingerprint,
    data: Data,
    client: any ResumableClient,
    storageApi: StorageApi,
    options: ResumableUploadOptions
  ) {
    self.fingerprint = fingerprint
    self.data = data
    self.client = client
    self.storageApi = storageApi
    self.options = options

    let (stream, continuation) = AsyncStream<ResumableUploadState>.makeStream()
    self.state = stream
    self.stateContinuation = continuation
  }

  deinit {
    stateContinuation.finish()
  }

  public func pause() {
    isPaused = true
  }

  public func cancel() async {
    isCancelled = true
    stateContinuation.finish()
  }

  public func start() async throws {
    do {
      try await performUpload()
    } catch {
      stateContinuation.finish()
      throw error
    }
  }

  private func performUpload() async throws {
    let cacheEntry = try await getCacheEntry()
    guard let uploadURL = URL(string: cacheEntry.uploadURL) else {
      throw StorageError(statusCode: nil, message: "Invalid upload URL", error: nil)
    }

    currentOffset = try await getUploadOffset(url: uploadURL)

    while currentOffset < data.count && !isCancelled {
      if isPaused {
        await emitState(cacheEntry: cacheEntry, paused: true)
        try await waitForResume()
        continue
      }

      let chunkSize = min(options.chunkSize, Int64(data.count) - currentOffset)
      let chunk = data.subdata(in: Int(currentOffset)..<Int(currentOffset + chunkSize))

      var retryCount = 0
      var success = false

      while retryCount < options.retryLimit && !success && !isCancelled {
        do {
          try await uploadChunk(chunk: chunk, offset: currentOffset, url: uploadURL)
          currentOffset += chunkSize
          success = true
          await emitState(cacheEntry: cacheEntry, paused: false)
        } catch {
          retryCount += 1
          if retryCount < options.retryLimit {
            try await Task.sleep(nanoseconds: UInt64(options.retryDelay * 1_000_000_000))
          } else {
            throw error
          }
        }
      }

      if !success {
        throw StorageError(
          statusCode: nil,
          message: "Upload failed after \(options.retryLimit) retries",
          error: nil
        )
      }
    }

    if currentOffset >= data.count && !isCancelled {
      await emitState(cacheEntry: cacheEntry, paused: false)
      stateContinuation.finish()
    }
  }

  private func getCacheEntry() async throws -> ResumableCacheEntry {
    if let existingEntry = try await client.continueUpload(
      fingerprint: fingerprint,
      cacheEntry: try await getCachedEntry()
    ) {
      return existingEntry
    }

    return try await client.createUpload(
      fingerprint: fingerprint,
      path: fingerprint.source,
      bucketId: "default",
      contentLength: Int64(data.count),
      contentType: "application/octet-stream",
      upsert: false,
      metadata: [:]
    )
  }

  private func getCachedEntry() async throws -> ResumableCacheEntry {
    // This is a placeholder - in real implementation, you'd get this from cache
    // For now, create a minimal entry to trigger creation
    return ResumableCacheEntry(
      uploadURL: "",
      path: fingerprint.source,
      bucketId: "default",
      expiration: Date(),
      upsert: false,
      contentType: "application/octet-stream"
    )
  }

  private func getUploadOffset(url: URL) async throws -> Int64 {
    var request = Helpers.HTTPRequest(url: url, method: .head)
    request.headers[.tusResumable] = ResumableClientImpl.tusVersion

    let response = try await storageApi.execute(request)

    guard
      let offsetHeader = response.headers[.uploadOffset],
      let offset = Int64(offsetHeader)
    else {
      return 0
    }

    return offset
  }

  private func uploadChunk(chunk: Data, offset: Int64, url: URL) async throws {
    var request = Helpers.HTTPRequest(url: url, method: .patch)
    request.headers[.tusResumable] = ResumableClientImpl.tusVersion
    request.headers[.contentType] = "application/offset+octet-stream"
    request.headers[.uploadOffset] = "\(offset)"
    request.body = chunk

    _ = try await storageApi.execute(request)
  }

  private func emitState(cacheEntry: ResumableCacheEntry, paused: Bool) async {
    let status = UploadStatus(
      totalBytesSent: currentOffset,
      contentLength: Int64(data.count)
    )

    let uploadState = ResumableUploadState(
      fingerprint: fingerprint,
      cacheEntry: cacheEntry,
      status: status,
      paused: paused
    )

    stateContinuation.yield(uploadState)
  }

  private func waitForResume() async throws {
    while isPaused && !isCancelled {
      try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    }
  }
}

extension StorageFileApi {
  public func resumableUpload(
    path: String,
    data: Data,
    options: ResumableUploadOptions = ResumableUploadOptions()
  ) throws -> ResumableUpload {
    let fingerprint = Fingerprint(source: path, size: Int64(data.count))
    let cache = createDefaultResumableCache()
    let client = ResumableClientImpl(storageApi: self, cache: cache)

    return ResumableUpload(
      fingerprint: fingerprint,
      data: data,
      client: client,
      storageApi: self,
      options: options
    )
  }
}
