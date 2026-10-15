//
//  ResumableUploadConfiguration.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

public import Foundation

/// How ``ResumableUpload`` chunks, retries and persists an upload.
///
/// Set it on ``StorageClientConfiguration/resumable``.
public struct ResumableUploadConfiguration: Sendable {
  /// The bytes sent per request. Hosted Supabase accepts exactly 6 MiB, the default, for every
  /// chunk but the last; a self-hosted Storage can be configured for another size.
  public var chunkSize: Int64

  /// How long an upload keeps retrying after a network failure before it fails. The waits
  /// between attempts grow with jitter; once their sum passes this, the upload is
  /// ``ResumableUpload/State/failed(_:)`` and its record stays for a later ``ResumableUpload/resume()``.
  public var retryTimeout: Duration

  /// Where upload records and sandbox copies live. `nil` uses `Application Support`; pass an app
  /// group container to share uploads with an extension.
  public var directory: URL?

  /// Creates a configuration.
  public init(
    chunkSize: Int64 = 6 * 1024 * 1024,
    retryTimeout: Duration = .seconds(60),
    directory: URL? = nil
  ) {
    self.chunkSize = chunkSize
    self.retryTimeout = retryTimeout
    self.directory = directory
  }
}
