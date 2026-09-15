//
//  HTTPBodyOutputStreamBridge.swift
//  Helpers
//
//  Created by Guilherme Souza on 15/09/26.
//

#if !canImport(FoundationNetworking)
  import Foundation

  /// Pumps an ``HTTPBody`` into the write end of a bound stream pair so `URLSession` can read
  /// the other end as a streamed request body.
  ///
  /// The bridge pulls one chunk at a time and writes only while the stream reports space, so
  /// the body is never read further ahead than the pair's buffer plus one chunk. Stream events
  /// and all mutable state live on one private queue. A ``HTTPBody/Length/known(_:)`` body that
  /// yields a different number of bytes fails with ``HTTPBodyLengthMismatchError``: the declared
  /// count has already gone out as `Content-Length`, and a short body would otherwise leave
  /// `URLSession` waiting for bytes that never come.
  final class HTTPBodyOutputStreamBridge: NSObject, StreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "supabase.HTTPBodyOutputStreamBridge")

    private let output: OutputStream
    private let declaredLength: Int64?
    private let onFailure: @Sendable (any Error) -> Void
    // Touched only on `queue`.
    private var iterator: HTTPBody.Iterator
    private var pending: ArraySlice<UInt8> = []
    private var pulled: Int64 = 0
    private var fetch: Task<Void, Never>?
    private var isClosed = false

    /// Starts pumping `body` into `output`. Calls `onFailure` at most once, when the body throws,
    /// the stream fails, or the body's byte count disagrees with its declared length; reaching
    /// the end of the body just closes the stream.
    init(
      body: HTTPBody, output: OutputStream, onFailure: @escaping @Sendable (any Error) -> Void
    ) {
      self.output = output
      self.onFailure = onFailure
      self.iterator = body.makeAsyncIterator()
      if case .known(let count) = body.length {
        declaredLength = count
      } else {
        declaredLength = nil
      }
      super.init()
      output.delegate = self
      CFWriteStreamSetDispatchQueue(output as CFWriteStream, queue)
      output.open()
    }

    deinit {
      output.delegate = nil
    }

    /// Stops pumping and closes the write end. Safe to call more than once.
    func cancel() {
      queue.async { self.close() }
    }

    func stream(_ stream: Stream, handle event: Stream.Event) {
      switch event {
      case .openCompleted, .hasSpaceAvailable:
        pump()
      case .errorOccurred:
        fail(stream.streamError ?? URLError(.unknown))
      case .endEncountered:
        close()
      default:
        break
      }
    }

    /// Writes what it holds while the stream has space, then pulls the next chunk. Idle while a
    /// pull is in flight; the pull's completion re-enters here.
    private func pump() {
      guard !isClosed, fetch == nil else { return }
      if pending.isEmpty {
        fetch = Task { [self] in
          let result: Result<ArraySlice<UInt8>?, any Error>
          do {
            result = .success(try await iterator.next())
          } catch {
            result = .failure(error)
          }
          queue.async { self.resume(with: result) }
        }
        return
      }
      guard output.hasSpaceAvailable else { return }
      let written = pending.withUnsafeBytes { buffer -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        return output.write(base, maxLength: buffer.count)
      }
      guard written > 0 else {
        if written < 0 { fail(output.streamError ?? URLError(.unknown)) }
        return
      }
      pending = pending.dropFirst(written)
      pump()
    }

    private func resume(with result: Result<ArraySlice<UInt8>?, any Error>) {
      fetch = nil
      switch result {
      case .success(let chunk?):
        pulled += Int64(chunk.count)
        if let declaredLength, pulled > declaredLength {
          fail(HTTPBodyLengthMismatchError(declared: declaredLength, actual: pulled))
          return
        }
        pending = chunk
        pump()
      case .success(nil):
        // `pump` only pulls once `pending` is empty, so everything pulled has been written.
        if let declaredLength, pulled != declaredLength {
          fail(HTTPBodyLengthMismatchError(declared: declaredLength, actual: pulled))
          return
        }
        close()
      case .failure(let error):
        fail(error)
      }
    }

    private func fail(_ error: any Error) {
      guard !isClosed else { return }
      close()
      onFailure(error)
    }

    private func close() {
      guard !isClosed else { return }
      isClosed = true
      fetch?.cancel()
      output.close()
      output.delegate = nil
    }
  }
#endif
