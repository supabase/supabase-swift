import ConcurrencyExtras
import Foundation

/// An instance of a ResumableUpload
///
/// Consumers can maintain a reference to the upload to observe its status, pause, and resume the upload
public final class ResumableUpload: @unchecked Sendable {
  public let id: UUID
  public let context: [String: String]?

  weak var client: ResumableUploadClient?
  var statuses = LockIsolated<[Status]>([])
  var continuations = LockIsolated<[UUID: AsyncStream<Status>.Continuation]>([:])

  init(id: UUID, context: [String: String]?, client: ResumableUploadClient) {
    self.id = id
    self.context = context
    self.client = client
    self.statuses.setValue([.queued(id)])
  }

  func send(_ status: Status) {
    statuses.withValue { $0.append(status) }
    let currentContinuations = continuations.value
    currentContinuations.values.forEach { $0.yield(status) }
  }

  func finish() {
    let currentContinuations = continuations.value
    continuations.setValue([:])
    currentContinuations.values.forEach { $0.finish() }
  }

  public func currentStatus() -> Status {
    statuses.value.last ?? .queued(id)
  }

  public func status() -> AsyncStream<Status> {
    AsyncStream { continuation in
      let streamID = UUID()

      // Replay the last status
      if let status = self.statuses.value.last {
        continuation.yield(status)
      }

      continuations.withValue { $0[streamID] = continuation }
      continuation.onTermination = { @Sendable _ in
        self.continuations.withValue { _ = $0.removeValue(forKey: streamID) }
      }
    }
  }

  public func pause() throws {
    try client?.pause(id: id)
  }

  public func resume() throws -> Bool {
    guard let client else { return false }
    return try client.resume(id: id)
  }
}
