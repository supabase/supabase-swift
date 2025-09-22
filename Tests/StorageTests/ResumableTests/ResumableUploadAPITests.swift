import InlineSnapshotTesting
import Mocker
import TestHelpers
import TUSKit
import XCTest
import ConcurrencyExtras

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Storage

final class ResumableUploadAPITests: XCTestCase {
  var storage: SupabaseStorageClient!

  override func setUp() {
    super.setUp()

    storage = SupabaseStorageClient.test(
      supabaseURL: "http://localhost:54321/storage/v1",
      apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    )
  }

  override func tearDown() {
    super.tearDown()
    removeStoredUploads()
  }

  func removeStoredUploads() {
    let storageDirectory = ResumableUploadClient.storageDirectory(for: "bucket")
    try? FileManager.default.removeItem(at: storageDirectory)
  }

  func createUpload(removeExistingFile: Bool = true) async throws -> ResumableUpload {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    if removeExistingFile {
      try await api.remove(paths: ["file.txt"])
    }

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")
    return upload
  }

  func testCreateApi() throws {
    let api = storage.from("bucket").resumable
    XCTAssertEqual(api.bucketId, "bucket")
    XCTAssertEqual(api.configuration.url, storage.configuration.url)
  }

  func testUploadFileContext() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket").resumable
    let upload = try await api.upload(file: testFileURL, to: "file.txt")
    XCTAssertEqual(upload.context, [
      "objectName": "file.txt",
      "contentType": "text/plain",
      "bucketName": "bucket",
    ])
  }

  func testUploadFileStatus() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!
    
    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")

    var statuses = [ResumableUpload.Status]()
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .started(upload.id) }))
    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))
  }

  func testUploadDuplicateFileSucceedsWithUpsert() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")

    var statuses = [ResumableUpload.Status]()
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))

    let upload2 = try await resumable.upload(file: testFileURL, to: "file.txt", options: .init(upsert: true))
    var statuses2 = [ResumableUpload.Status]()
    for await status in upload2.status() {
      statuses2.append(status)
    }

    XCTAssertTrue(statuses2.contains(where: { $0 == .finished(upload2.id) }))
  }

  func testUploadDuplicateFileFailsWithoutUpsert() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")

    var statuses = [ResumableUpload.Status]()
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))

    let upload2 = try await resumable.upload(file: testFileURL, to: "file.txt")
    var statuses2 = [ResumableUpload.Status]()
    for await status in upload2.status() {
      statuses2.append(status)
    }

    // TODO: check that error == couldNotCreateFileOnServer
    XCTAssertTrue(statuses2.contains(where: {
      if case let .failed(id, _) = $0, id == upload2.id {
        true
      } else {
        false
      }
    }))
  }

  func testPauseAndResumeUpload() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")
    for await status in upload.status() {
      if status == .started(upload.id) {
        try upload.pause()
      }
    }

    let currentStatus = upload.currentStatus()
    if case let .failed(id, error) = currentStatus {
      XCTAssertEqual(id, upload.id)
      XCTAssertEqual(error.localizedDescription, TUSClientError.taskCancelled.localizedDescription)
    } else {
      XCTFail()
    }

    let didResume = try upload.resume()
    XCTAssertTrue(didResume)

    var statuses = [ResumableUpload.Status]()
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))
  }

  func testCanceledUploadCannotBeResumed() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")
    for await status in upload.status() {
      if status == .started(upload.id) {
        // Pause the upload to simulate a transient failure
        try upload.pause()
      }
    }

    let currentStatus = upload.currentStatus()
    if case let .failed(id, error) = currentStatus {
      XCTAssertEqual(id, upload.id)
      XCTAssertEqual(error.localizedDescription, TUSClientError.taskCancelled.localizedDescription)
    } else {
      XCTFail()
    }

    // While the upload is technically in the failed state when paused,
    // it can be resumed unless the cache is cleared, which is what cancel does
    try await resumable.cancelUpload(id: upload.id)

    let didResume = try await resumable.resumeUpload(id: upload.id)
    XCTAssertFalse(didResume)
  }

  func testGetCurrentUploadStatus() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")
    for await status in upload.status() {
      let currentStatus = upload.currentStatus()
      XCTAssertEqual(status, currentStatus)
      let apiStatus = try await resumable.getUploadStatus(id: upload.id)
      XCTAssertEqual(status, apiStatus)
    }
  }

  func testResumeAllUploadsOnReinit() async throws {
    let testFileURL = Bundle.module.self.url(forResource: "file", withExtension: "txt")!
    let api = storage.from("bucket")
    let resumable = api.resumable

    try await api.remove(paths: ["file.txt"])

    var upload: ResumableUpload! = try await resumable.upload(file: testFileURL, to: "file.txt")
    let id = upload.id

    // make sure the weak client is deinit'd
    upload = nil

    // Simulate a
    _ = try await resumable.pauseAllUploads()

    // Remove existing client
    await resumable.clientStore.removeClient(for: "bucket")

    // Creates a new client on first method call
    _ = try await api.resumable.resumeAllUploads()
    upload = try await api.resumable.getUpload(id: id)
    XCTAssertNotNil(upload)

    var statuses: [ResumableUpload.Status] = []
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))
  }

  func testRetryFailedUpload() async throws {
    let testFileURL = Bundle.module.url(forResource: "file", withExtension: "txt")!

    let api = storage.from("bucket")

    // Remove existing file
    try await api.remove(paths: ["file.txt"])

    let resumable = api.resumable
    let upload = try await resumable.upload(file: testFileURL, to: "file.txt")
    for await status in upload.status() {
      if status == .started(upload.id) {
        try await api.resumable.cancelUpload(id: upload.id)
      }
    }

    let currentStatus = upload.currentStatus()
    if case let .failed(id, error) = currentStatus {
      XCTAssertEqual(id, upload.id)
      XCTAssertEqual(error.localizedDescription, TUSClientError.taskCancelled.localizedDescription)
    } else {
      XCTFail()
    }

    let didRetry = try await resumable.retryUpload(id: upload.id)
    XCTAssertTrue(didRetry)

    var statuses = [ResumableUpload.Status]()
    for await status in upload.status() {
      statuses.append(status)
    }

    XCTAssertTrue(statuses.contains(where: { $0 == .finished(upload.id) }))
  }
}
