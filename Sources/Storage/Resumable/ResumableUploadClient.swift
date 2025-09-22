import ConcurrencyExtras
import Foundation
import TUSKit

/// A wrapper around TUSClient
///
/// One client per bucket
final class ResumableUploadClient: @unchecked Sendable {
  let client: TUSClient
  let bucketId: String
  let url: URL
  let configuration: StorageClientConfiguration

  var activeUploads = LockIsolated<[UUID: ResumableUpload]>([:])

  // Track finished state if status is requested without a reference to a ResumableUpload
  var finishedUploads = LockIsolated<Set<UUID>>([])

  deinit {
    print("ResumableUploadClient deinit")
  }

  init(
    bucketId: String,
    configuration: StorageClientConfiguration
  ) throws {
    self.bucketId = bucketId
    self.configuration = configuration
    self.url = configuration.url.appendingPathComponent("/upload/resumable")

    let storageDirectory = Self.storageDirectory(for: bucketId)

    let client = try TUSClient(
      server: url,
      sessionIdentifier: bucketId,
      sessionConfiguration: configuration.resumableSessionConfiguration,
      storageDirectory: storageDirectory
    )

    self.client = client
    client.delegate = self
  }

  static func storageDirectory(for bucketId: String) -> URL {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TUS/\(bucketId)")
  }

  func uploadFile(
    filePath: URL,
    path: String,
    options: FileOptions = .init()
  ) throws -> ResumableUpload {

    let uploadURL = url
    var headers = configuration.headers
    headers["x-upsert"] = options.upsert ? "true" : "false"

    let context: [String: String] = [
      "bucketName": bucketId,
      "objectName": path,
      "contentType": options.contentType ?? mimeType(forPathExtension: filePath.pathExtension)
    ]

    // TODO: resume stored upload and check if there's already an active upload

    let id = try client.uploadFileAt(
      filePath: filePath,
      uploadURL: uploadURL,
      customHeaders: headers,
      context: context
    )

    let upload = ResumableUpload(id: id, context: context, client: self)
    activeUploads.withValue {
        $0[id] = upload
    }

    return upload
  }

  func upload(
    data: Data,
    path: String,
    pathExtension: String? = nil,
    options: FileOptions = .init()
  ) throws -> ResumableUpload {

    let uploadURL = url
    var headers = configuration.headers
    headers["x-upsert"] = options.upsert ? "true" : "false"

    var context: [String: String] = [
      "bucketName": bucketId,
      "objectName": path,
    ]

    if let contentType = pathExtension ?? options.contentType {
      context["contentType"] = contentType
    }

    // TODO: check if there's already an active upload and resume a stored upload that has not been created
    let id = try client.upload(
      data: data,
      uploadURL: uploadURL,
      customHeaders: headers,
      context: context
    )

    let upload = ResumableUpload(id: id, context: context, client: self)
    activeUploads.withValue {
        $0[id] = upload
    }

    return upload
  }

  func status(id: UUID) -> ResumableUpload.Status? {
    if let activeUpload = activeUploads.value[id] {
      return activeUpload.currentStatus()
    } else if finishedUploads.value.contains(id) {
      return .finished(id)
    } else {
      return nil
    }

    // TODO: check TUSClient if we don't have an active upload stored
  }

  func upload(for id: UUID) -> ResumableUpload? {
    activeUploads.value[id]
  }

  func pause(id: UUID) throws {
    try client.cancel(id: id)
  }

  func pauseAllUploads() throws {
    client.stopAndCancelAll()
  }

  func resume(id: UUID) throws -> Bool {
    return try client.resume(id: id)
  }

  func resumeAllUploads() throws {
    let storedUploads = client.start()
    activeUploads.withValue {
      for (id, context) in storedUploads {
        // Ensure we don't overwrite an upload that is created in `didStartUpload`
        if $0.keys.contains(id) { continue }
        $0[id] = ResumableUpload(id: id, context: context, client: self)
      }
    }
  }

  func retry(id: UUID) throws -> Bool {
    return try client.retry(id: id)
  }

  func cancel(id: UUID) throws {
    try client.cancel(id: id)
    try client.removeCacheFor(id: id)
  }

  func cancelAllUploads() throws {
    try client.reset()
  }
}

extension ResumableUploadClient: TUSClientDelegate {
  func didStartUpload(id: UUID, context: [String: String]?, client: TUSClient) {
    if let upload = activeUploads.value[id] {
      upload.send(.started(id))
    } else {
      // If an upload was resumed and it's not stored, create one
      let upload = ResumableUpload(id: id, context: context, client: self)
      activeUploads.withValue { $0[id] = upload }
      upload.send(.started(id))
    }
  }

  func progressFor(id: UUID, context: [String: String]?, bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
    if let upload = activeUploads.value[id] {
      upload.send(.progress(id, uploaded: bytesUploaded, total: totalBytes))
    }
  }

  func didFinishUpload(id: UUID, url: URL, context: [String: String]?, client: TUSClient) {
    _ = finishedUploads.withValue { $0.insert(id) }

    if let upload = activeUploads.value[id] {
      upload.send(.finished(id))
      upload.finish()
      activeUploads.withValue { _ = $0.removeValue(forKey: id) }
    }
  }

  func uploadFailed(id: UUID, error: any Error, context: [String: String]?, client: TUSClient) {
    if let upload = activeUploads.value[id] {
      upload.send(.failed(id, error))
      upload.finish()
      // TODO: not sure if the upload should be removed if it fails
//      activeUploads.withValue { _ = $0.removeValue(forKey: id) }
    }
  }

  func fileError(error: TUSClientError, client: TUSClient) {
      // TODO: emit file error
//    onFileError?(error)
  }

  func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSClient) {
      // TODO: emit total progress (for all upload)
//    onTotalProgress?(bytesUploaded, totalBytes)
  }
}
