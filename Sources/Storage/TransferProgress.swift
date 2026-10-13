//
//  TransferProgress.swift
//  Storage
//
//  Created by Guilherme Souza on 13/10/26.
//

import Foundation

/// How far an upload or a download has got.
///
/// Passed to the `progress:` closure of the upload and download methods on ``StorageBucket``.
/// The closure is called once per chunk the transfer moves, with no throttling, on no particular
/// actor. Hop to the main actor before you touch UI state:
///
/// ```swift
/// try await bucket.upload(path: "video.mp4", fileURL: url) { progress in
///   Task { @MainActor in model.fraction = progress.fractionCompleted ?? 0 }
/// }
/// ```
public struct TransferProgress: Hashable, Sendable {
  /// The bytes moved so far.
  public let completedBytes: Int64
  /// The bytes the transfer will move in total, or `nil` when the size is not known up front.
  public let totalBytes: Int64?

  /// Creates a progress value.
  public init(completedBytes: Int64, totalBytes: Int64?) {
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
  }

  /// `completedBytes / totalBytes`, from `0` to `1`, or `nil` when ``totalBytes`` is unknown or
  /// zero.
  public var fractionCompleted: Double? {
    guard let totalBytes, totalBytes > 0 else { return nil }
    return Double(completedBytes) / Double(totalBytes)
  }
}

extension TransferProgress {
  init(completedBytes: Int64, of length: HTTPBody.Length) {
    let total: Int64? = if case .known(let count) = length { count } else { nil }
    self.init(completedBytes: completedBytes, totalBytes: total)
  }
}
