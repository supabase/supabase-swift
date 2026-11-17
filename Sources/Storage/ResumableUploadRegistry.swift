//
//  ResumableUploadRegistry.swift
//  Storage
//
//  Created by Guilherme Souza on 15/10/26.
//

import Foundation

extension StorageClient {
  /// The resumable uploads this client's ``StorageClient/Configuration/resumable`` directory
  /// holds records for: the ones in flight, paused, or left by a previous run.
  ///
  /// - Warning: Experimental. See ``ResumableUpload``.
  @_spi(Experimental)
  public var resumableUploads: ResumableUploadRegistry {
    ResumableUploadRegistry(api: api)
  }
}

/// Finds the resumable uploads a client left behind and continues them.
///
/// ```swift
/// // At launch:
/// for outcome in try await storage.resumableUploads.resumeAll() {
///   if let error = outcome.error {
///     print("\(outcome.upload.path) did not resume: \(error)")
///     continue
///   }
///   Task { try await outcome.upload.result }
/// }
/// ```
/// - Warning: Experimental. See ``ResumableUpload``.
@_spi(Experimental)
public struct ResumableUploadRegistry: Sendable {
  /// What ``ResumableUploadRegistry/resumeAll()`` did with one upload.
  public struct ResumeOutcome: Sendable {
    /// The handle for the upload.
    public let upload: ResumableUpload
    /// The error ``ResumableUpload/start()`` or ``ResumableUpload/resume()`` threw, or `nil` when
    /// the upload went on.
    public let error: StorageError?
  }

  let api: StorageAPI

  private var store: ResumableStore {
    ResumableStore(configuration: api.configuration.resumable)
  }

  /// A handle for every record on disk, oldest first. An upload already in flight in this
  /// process is returned as the same handle; the others are ``ResumableUpload/Status/pending``
  /// until ``ResumableUpload/start()``. A record that does not decode is deleted; one that
  /// cannot be read, for example while data protection locks it, is skipped. Reads the disk off
  /// the caller's actor.
  ///
  /// - Throws: ``StorageError`` when the record directory cannot be read.
  @concurrent
  public func pending() async throws -> [ResumableUpload] {
    try store.records().map { ResumableUpload.handle(record: $0, api: api) }
  }

  /// ``pending()``, with every upload started or resumed, one at a time.
  ///
  /// Each ``ResumeOutcome`` holds a handle and the error its ``ResumableUpload/start()`` or
  /// ``ResumableUpload/resume()`` threw, or `nil` when the upload went on. A failed upload is
  /// also ``ResumableUpload/Status/failed(_:)``. An upload the server reports as expired or gone
  /// is created again from offset 0, not failed. A failure after the first request shows in that
  /// upload's ``ResumableUpload/result``.
  ///
  /// ```swift
  /// for outcome in try await storage.resumableUploads.resumeAll() {
  ///   if let error = outcome.error {
  ///     print("\(outcome.upload.path) did not resume: \(error)")
  ///     continue
  ///   }
  ///   Task { _ = try await outcome.upload.result }
  /// }
  /// ```
  ///
  /// - Returns: One ``ResumeOutcome`` for every upload ``pending()`` returns, in the same order.
  /// - Throws: ``StorageError`` when the record directory cannot be read, or
  ///   `CancellationError` when the calling task is cancelled. The uploads that started before
  ///   go on; ``pending()`` returns their handles.
  public func resumeAll() async throws -> [ResumeOutcome] {
    var outcomes: [ResumeOutcome] = []
    for upload in try await pending() {
      do {
        switch await upload.status {
        case .pending: try await upload.start()
        case .paused, .failed: try await upload.resume()
        case .uploading, .completed, .cancelled: break
        }
        outcomes.append(ResumeOutcome(upload: upload, error: nil))
      } catch let error as StorageError {
        outcomes.append(ResumeOutcome(upload: upload, error: error))
      }
    }
    return outcomes
  }

  /// Deletes the record and sandbox copy of every upload that is not in flight in this
  /// process. An upload in flight keeps its files until it completes or is cancelled, and a
  /// record that cannot be read, for example while data protection locks it, is kept. Works on
  /// the disk off the caller's actor.
  ///
  /// - Throws: ``StorageError`` when the record directory cannot be read.
  @concurrent
  public func clear() async throws {
    let store = store
    for record in try store.records() {
      ResumableUpload.removeUnlessLive(record, from: store, api: api)
    }
  }
}
