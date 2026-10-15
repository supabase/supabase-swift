//
//  ResumableUploadRegistry.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import Foundation

extension StorageClient {
  /// The resumable uploads this client's ``StorageClientConfiguration/resumable`` directory
  /// holds records for: the ones in flight, paused, or left by a previous run.
  public var resumableUploads: ResumableUploadRegistry {
    ResumableUploadRegistry(api: api)
  }
}

/// Finds the resumable uploads a client left behind and continues them.
///
/// ```swift
/// // At launch:
/// for upload in try await storage.resumableUploads.resumeAll() {
///   Task { try await upload.result }
/// }
/// ```
public struct ResumableUploadRegistry: Sendable {
  let api: StorageAPI

  private var store: ResumableStore {
    ResumableStore(configuration: api.configuration.resumable)
  }

  /// A handle for every record on disk, oldest first. An upload already in flight in this
  /// process is returned as the same handle; the others are ``ResumableUpload/State/pending``
  /// until ``ResumableUpload/start()``.
  ///
  /// - Throws: The file system's error when the record directory cannot be read.
  public func pending() throws -> [ResumableUpload] {
    try store.records().map { ResumableUpload.handle(record: $0, api: api) }
  }

  /// ``pending()``, with every upload started or resumed. A refusal by the server does not
  /// throw here; it shows in that upload's ``ResumableUpload/state`` and ``ResumableUpload/result``.
  ///
  /// - Throws: The file system's error when the record directory cannot be read.
  public func resumeAll() async throws -> [ResumableUpload] {
    let uploads = try pending()
    for upload in uploads {
      switch await upload.state {
      case .pending: try? await upload.start()
      case .paused, .failed: try? await upload.resume()
      case .uploading, .completed, .cancelled: break
      }
    }
    return uploads
  }

  /// Deletes every record and sandbox copy. Uploads in flight keep going and write their
  /// record again on the next chunk.
  ///
  /// - Throws: The file system's error when the directory cannot be removed.
  public func clear() throws {
    try store.removeAll()
  }
}
