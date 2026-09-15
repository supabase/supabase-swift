//
//  HTTPBody.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

import ConcurrencyExtras
public import Foundation

/// A streaming HTTP body: an async sequence of byte chunks with a length hint and an
/// iteration-behavior flag.
///
/// One type carries both request and response bodies through ``ClientTransport`` and
/// ``ClientMiddleware``. Buffered callers collect it with ``Foundation/Data/init(collecting:upTo:)``;
/// streaming callers iterate it directly.
///
/// ```swift
/// let body = HTTPBody(Data("{}".utf8))            // .known(2), .multiple
/// let file = try HTTPBody(fileURL: url)          // .known(size), .multiple
/// let data = try await Data(collecting: body, upTo: 1 << 20)
/// ```
///
/// A body whose ``iterationBehavior`` is ``IterationBehavior/single`` can be iterated once; a
/// second iteration throws ``HTTPBodyAlreadyConsumedError``. Retrying middleware must check
/// the flag before replaying a request.
public final class HTTPBody: AsyncSequence, @unchecked Sendable {
  public typealias Element = ArraySlice<UInt8>

  /// How many bytes the body holds, when known up front.
  public enum Length: Sendable, Hashable {
    /// The exact byte count. Transports send it as `Content-Length`.
    case known(Int64)
    /// Unknown. Transports fall back to chunked framing.
    case unknown
  }

  /// Whether the body can be iterated more than once.
  public enum IterationBehavior: Sendable, Hashable {
    /// One pass only. Retries must not replay it.
    case single
    /// Any number of passes, each yielding the same bytes.
    case multiple
  }

  /// How the bytes are backed. Lets ``URLSessionTransport`` pick the right task type.
  package enum Storage: Sendable {
    case data(Data)
    case file(URL)
    case stream
  }

  /// The length hint.
  public let length: Length
  /// Whether the body can be iterated more than once.
  public let iterationBehavior: IterationBehavior
  package let storage: Storage
  /// Set by ``reportingProgress(_:)``. ``URLSessionTransport`` calls it from
  /// `didSendBodyData` for `.file` and `.data` bodies, which it uploads without iterating.
  package let onUploadProgress: (@Sendable (_ bytesSoFar: Int64) -> Void)?

  private let makeChunks: @Sendable () -> AsyncThrowingStream<ArraySlice<UInt8>, any Error>
  private let consumed = LockIsolated(false)

  /// Creates a body from in-memory bytes. ``length`` is ``Length/known(_:)`` and the body is
  /// ``IterationBehavior/multiple``.
  public convenience init(_ data: Data) {
    self.init(
      storage: .data(data), length: .known(Int64(data.count)), iterationBehavior: .multiple
    ) {
      AsyncThrowingStream { continuation in
        if !data.isEmpty { continuation.yield(ArraySlice(data)) }
        continuation.finish()
      }
    }
  }

  /// Creates a body that streams a file from disk. The file is re-opened on every iteration,
  /// so the body is ``IterationBehavior/multiple`` and safe to retry.
  ///
  /// - Throws: The `FileManager` error when the file's size cannot be read.
  public convenience init(fileURL: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    self.init(storage: .file(fileURL), length: .known(size), iterationBehavior: .multiple) {
      // Opened on the first pull and read 64 KiB per pull, so a consumer that stops early never
      // reads the rest of the file. `FileHandle` closes its descriptor when it is released.
      let handle = Box<FileHandle?>(nil)
      return AsyncThrowingStream {
        let open = try handle.value ?? FileHandle(forReadingFrom: fileURL)
        handle.value = open
        guard let chunk = try open.read(upToCount: 64 * 1024), !chunk.isEmpty else {
          try open.close()
          return nil
        }
        return ArraySlice(chunk)
      }
    }
  }

  /// Creates a body from any async sequence of byte chunks.
  ///
  /// - Parameters:
  ///   - chunks: The chunk source. Iterated once per pass, and pulled one element at a time
  ///     as the consumer asks, so nothing is read ahead.
  ///   - length: The byte count, if known.
  ///   - iterationBehavior: Pass ``IterationBehavior/multiple`` only if iterating `chunks`
  ///     again yields the same bytes.
  public convenience init<S: AsyncSequence & Sendable>(
    _ chunks: S,
    length: Length,
    iterationBehavior: IterationBehavior
  ) where S.Element == ArraySlice<UInt8> {
    self.init(storage: .stream, length: length, iterationBehavior: iterationBehavior) {
      let iterator = Box(chunks.makeAsyncIterator())
      return AsyncThrowingStream { try await iterator.value.next() }
    }
  }

  package init(
    storage: Storage,
    length: Length,
    iterationBehavior: IterationBehavior,
    onUploadProgress: (@Sendable (_ bytesSoFar: Int64) -> Void)? = nil,
    makeChunks: @escaping @Sendable () -> AsyncThrowingStream<ArraySlice<UInt8>, any Error>
  ) {
    self.storage = storage
    self.length = length
    self.iterationBehavior = iterationBehavior
    self.onUploadProgress = onUploadProgress
    self.makeChunks = makeChunks
  }

  /// Creates an iterator over the body's chunks.
  ///
  /// A ``IterationBehavior/single`` body returns an iterator that throws
  /// ``HTTPBodyAlreadyConsumedError`` on every call after the first.
  public func makeAsyncIterator() -> Iterator {
    if iterationBehavior == .single {
      let alreadyConsumed = consumed.withValue { value -> Bool in
        defer { value = true }
        return value
      }
      if alreadyConsumed {
        return Iterator(
          base: AsyncThrowingStream { $0.finish(throwing: HTTPBodyAlreadyConsumedError()) }
            .makeAsyncIterator())
      }
    }
    return Iterator(base: makeChunks().makeAsyncIterator())
  }

  /// The iterator over a body's chunks.
  public struct Iterator: AsyncIteratorProtocol {
    var base: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Iterator

    /// Advances to the next chunk. Throws ``HTTPBodyAlreadyConsumedError`` when a `.single`
    /// body is iterated a second time.
    public mutating func next() async throws -> ArraySlice<UInt8>? {
      try await base.next()
    }
  }
}

/// Thrown when a ``HTTPBody/IterationBehavior/single`` body is iterated a second time.
public struct HTTPBodyAlreadyConsumedError: Error, Sendable {
  /// Creates the error.
  public init() {}
}

/// Thrown by ``Foundation/Data/init(collecting:upTo:)`` when the body exceeds the cap.
public struct HTTPBodyTooLargeError: Error, Sendable {
  /// The cap that was exceeded, in bytes.
  public let maxBytes: Int

  /// Creates the error.
  ///
  /// - Parameter maxBytes: The cap that was exceeded, in bytes.
  public init(maxBytes: Int) {
    self.maxBytes = maxBytes
  }
}

extension Data {
  /// Collects a body into memory.
  ///
  /// - Parameters:
  ///   - body: The body to drain.
  ///   - maxBytes: Throw ``HTTPBodyTooLargeError`` once more than this many bytes arrive.
  public init(collecting body: HTTPBody, upTo maxBytes: Int) async throws {
    var data = Data()
    if case .known(let count) = body.length, count > 0 {
      // The declared length is a hint from the peer; never reserve more than the caller's cap.
      data.reserveCapacity(Int(clamping: Swift.min(count, Int64(maxBytes))))
    }
    for try await chunk in body {
      guard data.count + chunk.count <= maxBytes else {
        throw HTTPBodyTooLargeError(maxBytes: maxBytes)
      }
      data.append(contentsOf: chunk)
    }
    self = data
  }
}

extension HTTPBody {
  /// Streams the body to a file, chunk by chunk, creating or truncating it first.
  public func write(to fileURL: URL) async throws {
    guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }
    for try await chunk in self {
      try handle.write(contentsOf: chunk)
    }
  }

  /// Returns a body that reports the cumulative byte count each time a chunk passes through.
  ///
  /// Works in both directions: wrap a request body to observe upload progress, or a response
  /// body to observe download progress. ``length`` and ``iterationBehavior`` are preserved.
  ///
  /// A file-backed body stays file-backed, so wrapping it does not change how
  /// ``URLSessionTransport`` uploads it: the bytes still go straight from disk and progress
  /// comes from `URLSession`'s own byte counts instead of from re-reading the file.
  public func reportingProgress(
    _ onProgress: @escaping @Sendable (_ bytesSoFar: Int64) -> Void
  ) -> HTTPBody {
    let base = self
    return HTTPBody(
      storage: storage, length: length, iterationBehavior: iterationBehavior,
      onUploadProgress: { bytesSoFar in
        base.onUploadProgress?(bytesSoFar)
        onProgress(bytesSoFar)
      }
    ) {
      let iterator = Box(base.makeAsyncIterator())
      let total = Box<Int64>(0)
      return AsyncThrowingStream {
        guard let chunk = try await iterator.value.next() else { return nil }
        total.value += Int64(chunk.count)
        onProgress(total.value)
        return chunk
      }
    }
  }
}

/// Mutable state for a pull closure. The consuming `AsyncThrowingStream` serializes pulls, so
/// the value is never touched from two places at once.
private final class Box<Value>: @unchecked Sendable {
  var value: Value

  init(_ value: Value) {
    self.value = value
  }
}
