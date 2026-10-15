//
//  ResumableUpload.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Logging

/// A tus upload that can be paused, resumed, cancelled, and continued after the process
/// restarts.
///
/// Created by ``StorageBucket/resumableUpload(path:fileURL:options:)`` and
/// ``StorageBucket/resumableUpload(path:data:options:)``. Nothing is sent until ``start()``:
///
/// ```swift
/// let upload = try bucket.resumableUpload(path: "video.mp4", fileURL: url)
/// try await upload.start()
/// for await progress in upload.progress { … }
/// let object = try await upload.result
/// ```
///
/// The handle outlives whoever created it, like a `Task`. Cancelling a task that awaits
/// ``start()``, ``result``, ``progress`` or ``states`` only ends that await; the upload keeps
/// going until ``pause()``, ``cancel()``, completion or failure. After a network failure the
/// upload retries, with a `HEAD` for the server's offset before each attempt, until
/// ``ResumableUploadConfiguration/retryTimeout`` is spent; then it fails and its record stays
/// on disk for ``resume()``, in this process or the next.
public actor ResumableUpload {
  /// The identity of an upload: the same file to the same path in the same bucket has the same
  /// `ID`, whichever URL it is picked through.
  public struct ID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// Where an upload is.
  public enum State: Sendable {
    /// Created, not started.
    case pending
    /// Sending chunks, or waiting to retry.
    case uploading
    /// Stopped by ``ResumableUpload/pause()``; ``ResumableUpload/resume()`` continues it.
    case paused
    /// Every byte is on the server.
    case completed(UploadedObject)
    /// Gave up. A transport failure keeps the record, so ``ResumableUpload/resume()`` can try
    /// again; a server rejection removes it.
    case failed(StorageError)
    /// Stopped by ``ResumableUpload/cancel()``; the server's copy and the record are gone.
    case cancelled

    var isTerminal: Bool {
      switch self {
      case .completed, .failed, .cancelled: true
      case .pending, .uploading, .paused: false
      }
    }
  }

  enum Input: Sendable {
    case file(URL)
    case data(Data)
    case prepared(ResumableSource)
  }

  private enum Next {
    case append
    case resync
    case recreate
  }

  public nonisolated let id: ID
  /// The bucket the object goes to.
  public nonisolated let bucketId: String
  /// The path of the object in the bucket.
  public nonisolated let path: String
  /// The size of the upload.
  public nonisolated let totalBytes: Int64

  /// Where the upload is now. ``states`` reports every change.
  public private(set) var state: State = .pending {
    didSet {
      stateBroadcaster.yield(state)
      if state.isTerminal {
        stateBroadcaster.finish()
        progressBroadcaster.finish()
        Self.live.withValue { if $0[liveKey]?.upload === self { $0.removeValue(forKey: liveKey) } }
      }
    }
  }

  private let api: StorageAPI
  private let store: ResumableStore
  private let options: UploadOptions
  private let input: Input
  private var record: ResumableUploadRecord?
  private var loop: Task<Void, Never>?
  private var pauseRequested = false
  private var startInProgress = false
  private let progressBroadcaster = StreamBroadcaster<TransferProgress>(
    bufferingPolicy: .bufferingNewest(1))
  private let stateBroadcaster = StreamBroadcaster<State>(bufferingPolicy: .unbounded)

  /// The handles that are not yet terminal, one per record, so two callers asking for the
  /// same upload drive one tus session instead of two. Held weakly, so a handle that never
  /// starts lives only as long as its caller keeps it.
  private struct Live {
    weak var upload: ResumableUpload?
    var started = false
  }

  private static let live = LockIsolated<[String: Live]>([:])

  private nonisolated var liveKey: String { Self.liveKey(fingerprint: id.rawValue, api: api) }

  private static func liveKey(fingerprint: String, api: StorageAPI) -> String {
    ResumableStore(configuration: api.configuration.resumable).directory
      .appendingPathComponent(fingerprint).path
  }

  /// The live handle for `fingerprint`, or the one `make` builds.
  static func handle(
    fingerprint: String, api: StorageAPI, make: @Sendable () -> ResumableUpload
  ) -> ResumableUpload {
    let key = liveKey(fingerprint: fingerprint, api: api)
    return live.withValue { live in
      if let existing = live[key]?.upload { return existing }
      let upload = make()
      live = live.filter { $0.value.upload != nil }
      live[key] = Live(upload: upload)
      return upload
    }
  }

  /// Whether a handle for `fingerprint` has started and is not yet terminal in this process.
  static func isLive(fingerprint: String, api: StorageAPI) -> Bool {
    live.withValue { live in
      let entry = live[liveKey(fingerprint: fingerprint, api: api)]
      return entry?.upload != nil && entry?.started == true
    }
  }

  /// The live handle for `record`, or a pending one built from it.
  static func handle(record: ResumableUploadRecord, api: StorageAPI) -> ResumableUpload {
    handle(fingerprint: record.fingerprint, api: api) {
      ResumableUpload(
        id: ID(rawValue: record.fingerprint), bucketId: record.bucketId, path: record.path,
        totalBytes: record.totalBytes, input: .prepared(record.source),
        options: UploadOptions(
          contentType: record.contentType,
          cacheControl: CacheControl(rawValue: record.cacheControl),
          upsert: record.upsert, metadata: record.metadata),
        api: api)
    }
  }

  init(
    id: ID, bucketId: String, path: String, totalBytes: Int64, input: Input,
    options: UploadOptions, api: StorageAPI
  ) {
    self.id = id
    self.bucketId = bucketId
    self.path = path
    self.totalBytes = totalBytes
    self.input = input
    self.options = options
    self.api = api
    self.store = ResumableStore(configuration: api.configuration.resumable)
  }

  /// The server-confirmed bytes, as each chunk lands. A late subscriber gets the latest value
  /// first; the stream ends with the upload.
  public nonisolated var progress: AsyncStream<TransferProgress> { progressBroadcaster.stream() }

  /// Every change of ``state``, ending after a terminal one.
  public nonisolated var states: AsyncStream<State> { stateBroadcaster.stream() }

  /// The uploaded object once every byte is on the server.
  ///
  /// - Throws: The ``StorageError`` the upload failed with, or `CancellationError` after
  ///   ``cancel()`` or when the awaiting task is cancelled.
  public var result: UploadedObject {
    get async throws {
      let states = states
      if let outcome = try outcome(of: state) { return outcome }
      for await state in states {
        if let outcome = try outcome(of: state) { return outcome }
      }
      throw CancellationError()
    }
  }

  private func outcome(of state: State) throws -> UploadedObject? {
    switch state {
    case .completed(let object): object
    case .failed(let error): throw error
    case .cancelled: throw CancellationError()
    case .pending, .uploading, .paused: nil
    }
  }

  // MARK: - Control

  /// Creates the upload on the server, or finds the one a previous run left, and starts
  /// sending chunks. Returns as soon as the first request is answered; ``result`` awaits the
  /// rest. Does nothing once started.
  ///
  /// - Throws: ``StorageError`` when the server refuses the upload, in which case ``state`` is
  ///   ``State/failed(_:)``.
  public func start() async throws {
    // The actor is reentrant across the await below, so a second start() must not reach
    // create(); it would open a second tus upload and overwrite the record.
    guard case .pending = state, !startInProgress else { return }
    startInProgress = true
    defer { startInProgress = false }
    do {
      let record = try await loadOrCreateRecord()
      guard case .pending = state else { return }
      self.record = record
      Self.live.withValue { live in
        if live[liveKey]?.upload == nil || live[liveKey]?.upload === self {
          live[liveKey] = Live(upload: self, started: true)
        }
      }
      state = .uploading
      startLoop(from: record.lastKnownOffset, next: .append)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let error = storageError(error)
      state = .failed(error)
      throw error
    }
  }

  /// Stops after the chunk in flight lands. The record stays, so ``resume()`` continues from
  /// the server's offset.
  public func pause() {
    guard case .uploading = state else { return }
    pauseRequested = true
    state = .paused
  }

  /// Continues a paused or failed upload from the offset the server reports.
  public func resume() async throws {
    switch state {
    case .paused, .failed: break
    case .pending, .uploading, .completed, .cancelled: return
    }
    await loop?.value
    guard record != nil else { return try await start() }
    state = .uploading
    startLoop(from: 0, next: .resync)
  }

  /// Aborts the upload: the chunk in flight is dropped, the server's copy is deleted (best
  /// effort), and so are the record and any sandbox copy.
  public func cancel() async {
    guard !state.isTerminal else { return }
    loop?.cancel()
    state = .cancelled
    await loop?.value
    if let record {
      await TusSession(api: api).terminate(record.uploadURL)
      try? store.remove(record)
    }
  }

  var isRunning: Bool { loop != nil }

  // MARK: - Upload loop

  private func startLoop(from offset: Int64, next: Next) {
    pauseRequested = false
    loop = Task { await run(from: offset, next: next) }
  }

  private func run(from start: Int64, next first: Next) async {
    let tus = TusSession(api: api)
    var offset = start
    var next = first
    var retry = 0
    var waited = Duration.zero
    while !pauseRequested, let record {
      do {
        switch next {
        case .resync:
          offset = try await tus.offset(of: record.uploadURL)
          next = .append
        case .recreate:
          offset = try await recreate(record).lastKnownOffset
          next = .append
        case .append:
          guard let more = try await append(at: offset, with: tus) else { break }
          offset = more
          retry = 0
          waited = .zero
          continue
        }
      } catch is CancellationError {
        break
      } catch TusSession.Failure.offsetConflict {
        next = .resync
      } catch TusSession.Failure.uploadGone {
        next = .recreate
      } catch let error as StorageError where error.kind == .transport {
        retry += 1
        let delay = RetryPolicy.default.backoffDelay(retry: retry)
        waited += delay
        guard waited <= api.configuration.resumable.retryTimeout else {
          fail(error, keepRecord: true)
          break
        }
        api.configuration.logger.debug(
          "Resumable upload \(id.rawValue) retrying in \(delay) after: \(error.message)")
        try? await api.configuration.clock.sleep(for: delay)
        if Task.isCancelled { break }
        next = .resync
      } catch {
        fail(storageError(error), keepRecord: false)
        break
      }
      if state.isTerminal { break }
    }
    loop = nil
  }

  /// Sends the chunk at `offset` and returns the server's new offset, or `nil` once the upload
  /// is complete.
  private func append(at offset: Int64, with tus: TusSession) async throws -> Int64? {
    guard var record else { return nil }
    if offset < totalBytes {
      let chunk = try await Self.read(
        store.fileURL(for: record), at: offset, count: record.chunkSize)
      let appended = try await tus.append(chunk, at: offset, to: record.uploadURL)
      record.lastKnownOffset = appended.offset
      self.record = record
      try store.save(record)
      progressBroadcaster.yield(
        TransferProgress(completedBytes: appended.offset, totalBytes: totalBytes))
      guard appended.complete || appended.offset >= totalBytes else { return appended.offset }
      complete(with: appended.body)
    } else {
      complete(with: Data())
    }
    return nil
  }

  private func complete(with body: Data) {
    let response = try? JSONDecoder.storage.decode(UploadResponse.self, from: body)
    let object = UploadedObject(
      id: response?.id.flatMap(UUID.init(uuidString:)),
      path: path,
      fullPath: response?.key ?? "\(bucketId)/\(path)")
    if let record { try? store.remove(record) }
    state = .completed(object)
  }

  private func fail(_ error: StorageError, keepRecord: Bool) {
    if !keepRecord, let record { try? store.remove(record) }
    state = .failed(error)
  }

  // MARK: - Records

  private func loadOrCreateRecord() async throws -> ResumableUploadRecord {
    let tus = TusSession(api: api)
    if var existing = try store.record(fingerprint: id.rawValue) {
      do {
        existing.lastKnownOffset = try await tus.offset(of: existing.uploadURL)
        try store.save(existing)
        return existing
      } catch TusSession.Failure.uploadGone {
        return try await recreate(existing)
      }
    }
    let source =
      switch input {
      case .file(let fileURL): try await store.prepare(fileURL: fileURL, fingerprint: id.rawValue)
      case .data(let data): try store.prepare(data: data, fingerprint: id.rawValue)
      case .prepared(let source): source
      }
    return try await createRecord(source: source, with: tus)
  }

  /// Creates the upload again on the server for a record the server no longer knows.
  private func recreate(_ stale: ResumableUploadRecord) async throws -> ResumableUploadRecord {
    try? FileManager.default.removeItem(
      at: store.directory.appendingPathComponent("\(stale.fingerprint).json"))
    let record = try await createRecord(source: stale.source, with: TusSession(api: api))
    self.record = record
    return record
  }

  private func createRecord(source: ResumableSource, with tus: TusSession) async throws
    -> ResumableUploadRecord
  {
    let key = try ObjectKey(path)
    let (_, modificationDate) = try ResumableStore.attributes(
      of: store.fileURL(for: source, fingerprint: id.rawValue))
    let created = try await tus.create(
      bucket: bucketId, key: key, length: totalBytes, options: options)
    let now = Date()
    let record = ResumableUploadRecord(
      fingerprint: id.rawValue,
      bucketId: bucketId,
      path: path,
      totalBytes: totalBytes,
      source: source,
      sourceModificationDate: modificationDate,
      uploadURL: created.uploadURL,
      createdAt: now,
      expiresAt: created.expiresAt ?? now.addingTimeInterval(ResumableStore.defaultLifetime),
      lastKnownOffset: created.offset,
      chunkSize: api.configuration.resumable.chunkSize,
      upsert: options.upsert,
      contentType: options.contentType,
      cacheControl: options.cacheControl.rawValue,
      metadata: options.metadata)
    try store.save(record)
    return record
  }

  private nonisolated func storageError(_ error: any Error) -> StorageError {
    error as? StorageError
      ?? StorageError(
        kind: .invalidRequest, message: "The upload source could not be read.",
        underlyingError: error)
  }

  @concurrent
  private static func read(_ fileURL: URL, at offset: Int64, count: Int64) async throws -> Data {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(offset))
    return try handle.read(upToCount: Int(count)) ?? Data()
  }
}

/// Fans one producer out to any number of `AsyncStream` consumers. A new consumer gets the
/// latest element first.
final class StreamBroadcaster<Element: Sendable>: Sendable {
  private struct Subscribers {
    var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    var latest: Element?
    var finished = false
  }

  private let subscribers = LockIsolated(Subscribers())
  private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

  init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy) {
    self.bufferingPolicy = bufferingPolicy
  }

  func stream() -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Element.self, bufferingPolicy: bufferingPolicy)
    let id = UUID()
    subscribers.withValue { subscribers in
      if let latest = subscribers.latest { continuation.yield(latest) }
      if subscribers.finished {
        continuation.finish()
      } else {
        subscribers.continuations[id] = continuation
      }
    }
    continuation.onTermination = { [subscribers] _ in
      subscribers.withValue { _ = $0.continuations.removeValue(forKey: id) }
    }
    return stream
  }

  func yield(_ element: Element) {
    subscribers.withValue { subscribers in
      subscribers.latest = element
      for continuation in subscribers.continuations.values { continuation.yield(element) }
    }
  }

  func finish() {
    subscribers.withValue { subscribers in
      subscribers.finished = true
      for continuation in subscribers.continuations.values { continuation.finish() }
      subscribers.continuations.removeAll()
    }
  }
}
