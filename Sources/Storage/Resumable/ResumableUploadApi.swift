import ConcurrencyExtras
import Foundation
import HTTPTypes
import TUSKit

/// Supabase Resumable Upload API
public class ResumableUploadApi: StorageApi, @unchecked Sendable {
  let bucketId: String
  let clientStore: ResumableClientStore

  init(bucketId: String, configuration: StorageClientConfiguration, clientStore: ResumableClientStore) {
    self.bucketId = bucketId
    self.clientStore = clientStore
    super.init(configuration: configuration)
  }

  public func upload(file: URL, to path: String, options: FileOptions = .init()) async throws -> ResumableUpload {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    let upload = try client.uploadFile(filePath: file, path: path, options: options)
    return upload
  }

  public func upload(data: Data, to path: String, pathExtension: String? = nil, options: FileOptions = .init()) async throws -> ResumableUpload {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    let upload = try client.upload(data: data, path: path, pathExtension: pathExtension, options: options)
    return upload
  }

  public func pauseUpload(id: UUID) async throws {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    try client.pause(id: id)
  }

  public func pauseAllUploads() async throws {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    try client.pauseAllUploads()
  }

  public func resumeUpload(id: UUID) async throws -> Bool {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    return try client.resume(id: id)
  }

  public func retryUpload(id: UUID) async throws -> Bool {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    return try client.retry(id: id)
  }

  public func resumeAllUploads() async throws {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    try client.resumeAllUploads()
  }

  public func cancelUpload(id: UUID) async throws {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    try client.cancel(id: id)
  }

  public func cancelAllUploads() async throws {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    try client.cancelAllUploads()
  }

  public func getUploadStatus(id: UUID) async throws -> ResumableUpload.Status? {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    return client.status(id: id)
  }

  public func getUpload(id: UUID) async throws -> ResumableUpload? {
    let client = try await clientStore.getOrCreateClient(for: bucketId)
    return client.upload(for: id)
  }
}
