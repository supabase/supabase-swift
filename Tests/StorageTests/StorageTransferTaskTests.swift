//
//  StorageTransferTaskTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import ConcurrencyExtras
import Foundation
import Testing

@testable import Storage

@Suite struct StorageTransferTaskTests {

  @Test func transferProgressFractionCompleted() {
    let p = TransferProgress(bytesTransferred: 25, totalBytes: 100)
    #expect(p.fractionCompleted == 0.25)
  }

  @Test func transferProgressFractionCompletedWhenTotalIsZero() {
    let p = TransferProgress(bytesTransferred: 0, totalBytes: 0)
    #expect(p.fractionCompleted == 0)
  }

  @Test func eventsStreamDeliversProgressAndCompletion() async throws {
    let task = makeTask(success: "hello")
    var events: [TransferEvent<String>] = []
    for await event in task.events {
      events.append(event)
    }
    #expect(events.count == 2)
    if case .progress(let p) = events[0] {
      #expect(p.bytesTransferred == 10)
    } else {
      Issue.record("Expected .progress as first event")
    }
    if case .completed(let v) = events[1] {
      #expect(v == "hello")
    } else {
      Issue.record("Expected .completed as second event")
    }
  }

  @Test func resultReturnsSuccessValue() async throws {
    let task = makeTask(success: "world")
    let result = try await task.value
    #expect(result == "world")
  }

  @Test func resultThrowsOnFailure() async {
    let task: StorageTransferTask<String> = makeFailingTask(StorageError.cancelled)
    do {
      _ = try await task.value
      Issue.record("Expected throw")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func mapResultTransformsSuccess() async throws {
    let task = makeTask(success: 42)
    let mapped = task.mapResult { "\($0)" }
    let result = try await mapped.value
    #expect(result == "42")
  }

  @Test func mapResultForwardsProgress() async throws {
    let task = makeTask(success: 42)
    let mapped = task.mapResult { $0 * 2 }
    var progressSeen = false
    for await event in mapped.events {
      if case .progress = event { progressSeen = true }
    }
    #expect(progressSeen)
  }

  @Test func mapResultPropagatesFailure() async {
    let task: StorageTransferTask<Int> = makeFailingTask(StorageError.cancelled)
    let mapped = task.mapResult { "\($0)" }
    do {
      _ = try await mapped.value
      Issue.record("Expected throw")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func cancelInvokesCancelClosure() async {
    let cancelCalled = LockIsolated(false)
    let (eventStream, _) = AsyncStream<TransferEvent<String>>.makeStream()
    let (resultStream, _) = AsyncStream<Result<String, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let resultTask = Task<String, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }
    let task = StorageTransferTask<String>(
      events: eventStream,
      resultTask: resultTask,
      pause: {},
      resume: {},
      cancel: { cancelCalled.setValue(true) }
    )
    await task.cancel()
    #expect(cancelCalled.value)
  }

  @Test func mapResultTransformThrowsPropagatesAsFailure() async {
    let task = makeTask(success: 42)
    let mapped = task.mapResult { (_: Int) throws -> String in
      throw NSError(domain: "test", code: 1)
    }
    var gotFailure = false
    for await event in mapped.events {
      if case .failed(let error) = event {
        gotFailure = true
        #expect(error.errorCode == .fileSystemError)
      }
    }
    #expect(gotFailure)
  }
}

// MARK: - Helpers

private func makeTask<Success: Sendable>(success value: Success) -> StorageTransferTask<Success> {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<Success>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<Success, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<Success, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let task = StorageTransferTask<Success>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  eventsContinuation.yield(.progress(TransferProgress(bytesTransferred: 10, totalBytes: 100)))
  eventsContinuation.yield(.completed(value))
  eventsContinuation.finish()
  resultContinuation.yield(.success(value))

  return task
}

private func makeFailingTask<Success: Sendable>(_ error: StorageError) -> StorageTransferTask<
  Success
> {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<Success>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<Success, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<Success, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let task = StorageTransferTask<Success>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  eventsContinuation.yield(.failed(error))
  eventsContinuation.finish()
  resultContinuation.yield(.failure(error))

  return task
}
