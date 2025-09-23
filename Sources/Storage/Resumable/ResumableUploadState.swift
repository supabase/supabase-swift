import Foundation

public struct UploadStatus: Sendable {
  public let totalBytesSent: Int64
  public let contentLength: Int64

  public init(totalBytesSent: Int64, contentLength: Int64) {
    self.totalBytesSent = totalBytesSent
    self.contentLength = contentLength
  }
}

public struct ResumableUploadState: Sendable {
  public let fingerprint: Fingerprint
  public let status: UploadStatus
  public let paused: Bool
  private let cacheEntry: ResumableCacheEntry

  public var path: String {
    cacheEntry.path
  }

  public var bucketId: String {
    cacheEntry.bucketId
  }

  public var isDone: Bool {
    status.totalBytesSent >= status.contentLength
  }

  public var progress: Float {
    guard status.contentLength > 0 else { return 0.0 }
    return Float(status.totalBytesSent) / Float(status.contentLength)
  }

  public init(
    fingerprint: Fingerprint,
    cacheEntry: ResumableCacheEntry,
    status: UploadStatus,
    paused: Bool
  ) {
    self.fingerprint = fingerprint
    self.cacheEntry = cacheEntry
    self.status = status
    self.paused = paused
  }
}