//
//  StorageDownloadIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 04/05/26.
//

// Requires: supabase start && supabase db reset (from Tests/IntegrationTests/)
// Run with: make test-integration

import Foundation
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
final class StorageDownloadIntegrationTests {

  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: ["Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"],
      logger: nil
    )
  )

  /// Creates a fresh private bucket, uploads a blob, then runs the test body.
  /// Always cleans up the bucket regardless of success or failure.
  private func withUploadedFile(
    size: Int = 1 * 1024 * 1024,
    byte: UInt8 = 0xAB,
    _ body: (_ bucket: String, _ path: String, _ data: Data) async throws -> Void
  ) async throws {
    let bucketId = "dl-test-\(UUID().uuidString.lowercased())"
    let path = "files/\(UUID().uuidString).bin"
    let data = Data(repeating: byte, count: size)

    try await storage.createBucket(bucketId, options: BucketOptions(isPublic: false))

    do {
      _ = try await storage.from(bucketId).upload(path, data: data).value
      try await body(bucketId, path, data)
    } catch {
      try? await storage.emptyBucket(bucketId)
      try? await storage.deleteBucket(bucketId)
      throw error
    }

    try? await storage.emptyBucket(bucketId)
    try? await storage.deleteBucket(bucketId)
  }

  // MARK: - Happy path

  /// Basic download completes and the file on disk matches what was uploaded.
  @Test func downloadToDiskMatchesUploadedContent() async throws {
    try await withUploadedFile { bucket, path, original in
      let url = try await storage.from(bucket).download(path: path).value
      defer { try? FileManager.default.removeItem(at: url) }

      #expect(FileManager.default.fileExists(atPath: url.path))
      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  /// `download()` emits at least one `.progress` event before `.completed`.
  @Test func downloadEmitsProgressEvents() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)
      var progressFractions: [Double] = []
      var completedURL: URL?

      for await event in task.events {
        switch event {
        case .progress(let p):
          progressFractions.append(p.fractionCompleted)
        case .completed(let url):
          completedURL = url
        case .failed(let error):
          Issue.record("Unexpected failure: \(error)")
        }
      }

      #expect(!progressFractions.isEmpty, "Expected at least one progress event")
      #expect(progressFractions.allSatisfy { $0 >= 0 && $0 <= 1.0 })

      let url = try #require(completedURL)
      defer { try? FileManager.default.removeItem(at: url) }
      #expect(FileManager.default.fileExists(atPath: url.path))
    }
  }

  /// `downloadData()` returns the exact bytes that were uploaded.
  @Test func downloadDataMatchesUploadedContent() async throws {
    try await withUploadedFile(size: 256 * 1024) { bucket, path, original in
      let received = try await storage.from(bucket).downloadData(path: path).value
      #expect(received == original)
    }
  }

  /// `.value` and `.events` are independent — consuming both yields consistent results.
  @Test func valueAndEventsAreIndependent() async throws {
    try await withUploadedFile(size: 512 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)

      // Consume events in a background task while simultaneously awaiting .value.
      async let eventCount: Int = {
        var count = 0
        for await _ in task.events { count += 1 }
        return count
      }()

      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let count = await eventCount
      #expect(count > 0, "Events stream should have delivered events")

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  // MARK: - Pause / resume

  /// Pausing immediately after starting and then resuming delivers the complete file.
  @Test func pauseThenResumeCompletesDownload() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)

      // Collect the first progress event, then pause.
      var paused = false
      for await event in task.events {
        if case .progress = event, !paused {
          paused = true
          await task.pause()
          break
        }
      }

      // Resume and collect the rest.
      await task.resume()
      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  /// Pausing before any data arrives (fire-pause-resume) still completes correctly.
  @Test func pauseBeforeFirstProgressThenResumeCompletes() async throws {
    try await withUploadedFile(size: 1 * 1024 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)

      // Pause immediately — may land before the first progress event.
      await task.pause()
      await task.resume()

      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  /// Multiple pause/resume cycles eventually complete the download.
  @Test func multiplePauseResumeCyclesCompleteDownload() async throws {
    try await withUploadedFile(size: 3 * 1024 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)

      actor Counters {
        var pauseCount = 0
        var progressCount = 0
        func incrementProgress() -> Int {
          progressCount += 1
          return progressCount
        }
        func incrementPause() -> Int {
          pauseCount += 1
          return pauseCount
        }
        func getPauseCount() -> Int { pauseCount }
      }
      let counters = Counters()

      // Drive the download manually: pause on every other progress event.
      Task {
        for await event in task.events {
          if case .progress = event {
            let progress = await counters.incrementProgress()
            let pauses = await counters.getPauseCount()
            if progress.isMultiple(of: 2) && pauses < 3 {
              _ = await counters.incrementPause()
              await task.pause()
              // Small delay before resuming to let the pause propagate.
              try? await Task.sleep(nanoseconds: 50_000_000)
              await task.resume()
            }
          }
        }
      }

      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let received = try Data(contentsOf: url)
      #expect(received == original)
      #expect(await counters.getPauseCount() > 0, "Expected at least one pause/resume cycle")
    }
  }

  /// Pausing a download that is already paused is a no-op — a subsequent resume still works.
  @Test func doublePauseIsIdempotent() async throws {
    try await withUploadedFile(size: 1 * 1024 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)

      await task.pause()
      await task.pause()  // second pause — should be a no-op
      await task.resume()

      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  /// Resuming a download that was never paused is a no-op — the download still completes.
  @Test func resumeWithoutPauseIsNoop() async throws {
    try await withUploadedFile(size: 512 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)
      await task.resume()  // no-op: not paused

      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  /// Resuming an already-completed download is a no-op — value is still available.
  @Test func resumeAfterCompletionIsNoop() async throws {
    try await withUploadedFile(size: 256 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)
      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      await task.resume()  // no-op: already completed

      let received = try Data(contentsOf: url)
      #expect(received == original)
    }
  }

  // MARK: - Cancel

  /// Cancelling a download causes `.value` to throw with `.cancelled` error code.
  @Test func cancelThrowsCancelledError() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)
      await task.cancel()

      do {
        _ = try await task.value
        Issue.record("Expected a StorageError to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }
    }
  }

  /// Cancelling a download causes the `events` stream to end with a `.failed(.cancelled)` event.
  @Test func cancelYieldsCancelledEventOnStream() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)
      await task.cancel()

      var lastEvent: TransferEvent<URL>?
      for await event in task.events { lastEvent = event }

      guard case .failed(let error) = lastEvent else {
        Issue.record("Expected .failed event, got \(String(describing: lastEvent))")
        return
      }
      #expect(error.errorCode == .cancelled)
    }
  }

  /// Cancelling mid-download (after at least one progress event) still delivers `.cancelled`.
  @Test func cancelMidDownloadDeliversCancelledError() async throws {
    try await withUploadedFile(size: 3 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)

      // Wait for first progress event, then cancel.
      for await event in task.events {
        if case .progress = event {
          await task.cancel()
          break
        }
      }

      do {
        _ = try await task.value
        Issue.record("Expected a StorageError to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }
    }
  }

  /// Cancelling an already-completed download is a no-op — value is still available.
  @Test func cancelAfterCompletionIsNoop() async throws {
    try await withUploadedFile(size: 256 * 1024) { bucket, path, original in
      let task = storage.from(bucket).download(path: path)
      let url = try await task.value
      defer { try? FileManager.default.removeItem(at: url) }

      await task.cancel()  // no-op: already completed

      // Value should still be readable (it was already stored in the result task).
      let url2 = try await task.value
      defer { try? FileManager.default.removeItem(at: url2) }

      let received = try Data(contentsOf: url2)
      #expect(received == original)
    }
  }

  /// Cancelling a paused download delivers `.cancelled`, not `.failed(.networkError)`.
  @Test func cancelWhilePausedDeliversCancelledError() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)
      await task.pause()
      await task.cancel()

      do {
        _ = try await task.value
        Issue.record("Expected a StorageError to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }
    }
  }

  /// Calling `cancel()` multiple times is safe — the second call is a no-op.
  @Test func doubleCancelIsIdempotent() async throws {
    try await withUploadedFile(size: 1 * 1024 * 1024) { bucket, path, _ in
      let task = storage.from(bucket).download(path: path)
      await task.cancel()
      await task.cancel()  // second cancel — should be a no-op

      do {
        _ = try await task.value
        Issue.record("Expected a StorageError to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }
    }
  }

  // MARK: - Error handling

  /// Downloading a path that does not exist results in a non-cancelled storage error.
  @Test func downloadNonExistentPathFails() async throws {
    try await withUploadedFile { bucket, _, _ in
      let task = storage.from(bucket).download(path: "does/not/exist.bin")

      do {
        _ = try await task.value
        Issue.record("Expected a StorageError to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode != .cancelled)
      }
    }
  }

  /// The `events` stream ends with `.failed` when the path does not exist.
  @Test func downloadNonExistentPathEmitsFailedEvent() async throws {
    try await withUploadedFile { bucket, _, _ in
      let task = storage.from(bucket).download(path: "does/not/exist.bin")
      var lastEvent: TransferEvent<URL>?
      for await event in task.events { lastEvent = event }

      guard case .failed = lastEvent else {
        Issue.record("Expected .failed event, got \(String(describing: lastEvent))")
        return
      }
    }
  }

  // MARK: - Concurrent downloads

  /// Multiple concurrent downloads from the same bucket all complete correctly.
  @Test func concurrentDownloadsCompleteIndependently() async throws {
    try await withUploadedFile(size: 512 * 1024, byte: 0x11) { bucket, path1, data1 in
      // Upload a second file.
      let path2 = "files/\(UUID().uuidString).bin"
      let data2 = Data(repeating: 0x22, count: 512 * 1024)
      _ = try await storage.from(bucket).upload(path2, data: data2).value

      // Capture storage to avoid sending `self` across async-let child tasks.
      let s = storage
      async let url1 = s.from(bucket).download(path: path1).value
      async let url2 = s.from(bucket).download(path: path2).value

      let (u1, u2) = try await (url1, url2)
      defer {
        try? FileManager.default.removeItem(at: u1)
        try? FileManager.default.removeItem(at: u2)
      }

      #expect(try Data(contentsOf: u1) == data1)
      #expect(try Data(contentsOf: u2) == data2)
    }
  }

  /// Cancelling one download does not affect a concurrent download.
  @Test func cancelOneDownloadDoesNotAffectAnother() async throws {
    try await withUploadedFile(size: 2 * 1024 * 1024, byte: 0xAA) { bucket, path1, original in
      let path2 = "files/\(UUID().uuidString).bin"
      let data2 = Data(repeating: 0xBB, count: 2 * 1024 * 1024)
      _ = try await storage.from(bucket).upload(path2, data: data2).value

      let task1 = storage.from(bucket).download(path: path1)
      let task2 = storage.from(bucket).download(path: path2)

      // Cancel task1 immediately; let task2 run to completion.
      await task1.cancel()

      do {
        _ = try await task1.value
        Issue.record("Expected task1 to throw .cancelled")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }

      let url2 = try await task2.value
      defer { try? FileManager.default.removeItem(at: url2) }
      #expect(try Data(contentsOf: url2) == data2)
    }
  }
}
