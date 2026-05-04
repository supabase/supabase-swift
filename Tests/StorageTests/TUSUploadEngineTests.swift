//
//  TUSUploadEngineTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized) struct TUSUploadEngineTests {

  let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
  let uploadURL = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
  let locationURL = URL(
    string: "https://example.supabase.co/storage/v1/upload/resumable/test-id")!

  var client: StorageClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: session
      )
    )
  }

  var sequentialClient: StorageClient {
    SequentialMockProtocol.reset()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SequentialMockProtocol.self]
    return StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: URLSession(configuration: config)
      )
    )
  }

  // MARK: - Helpers

  private func makeTUSServerResponseData(path: String, fullPath: String) throws -> Data {
    // TUSUploadServerResponse shape: {"Key": "<fullPath>", "Id": "<uuid>"}
    let json = "{\"Key\":\"\(fullPath)\",\"Id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\"}"
    return Data(json.utf8)
  }

  // MARK: - Tests

  @Test func postCreatesUploadWithCorrectHeaders() async throws {
    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var postMock = Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    )
    postMock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.setValue(request)
    })
    postMock.register()

    // Register a PATCH mock so the engine can proceed past POST without error
    let patchResponseJSON = """
      {"Key":"bucket/test.txt","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}
      """
    Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: Data(patchResponseJSON.utf8)],
      additionalHeaders: ["Upload-Offset": "5"]
    ).register()

    let data = Data("hello".utf8)
    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "test.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain", upsert: false),
      client: client
    )
    _ = try await task.result

    let request = try #require(capturedRequest.value)
    #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    #expect(request.value(forHTTPHeaderField: "Upload-Length") == "5")
    let metadata = try #require(request.value(forHTTPHeaderField: "Upload-Metadata"))
    #expect(metadata.contains("bucketName"))
    #expect(metadata.contains("objectName"))
    #expect(metadata.contains("contentType"))
    #expect(metadata.contains("cacheControl"))
  }

  @Test func sendsTwoChunksForDataLargerThanChunkSize() async throws {
    tusChunkSize = 3
    defer { tusChunkSize = 6 * 1024 * 1024 }

    let data = Data("hello".utf8)  // 5 bytes → 2 chunks (3 + 2)
    let finalResponse = try makeTUSServerResponseData(path: "f.txt", fullPath: "bucket/f.txt")

    let sc = sequentialClient
    SequentialMockProtocol.responses = [
      // POST: 201 + Location header
      (201, ["Location": locationURL.absoluteString], Data()),
      // PATCH 1 (offset 0, 3 bytes): 204 + Upload-Offset: 3
      (204, ["Upload-Offset": "3"], Data()),
      // PATCH 2 (offset 3, 2 bytes): 200 + final response body
      (200, ["Upload-Offset": "5"], finalResponse),
    ]

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "f.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain"),
      client: sc
    )
    _ = try await task.result

    // POST + 2 PATCHes = 3 total requests
    #expect(SequentialMockProtocol.callIndex == 3)
    let requests = SequentialMockProtocol.capturedRequests
    #expect(requests.count == 3)
    let patch1Offset = requests[1].value(forHTTPHeaderField: "Upload-Offset")
    let patch2Offset = requests[2].value(forHTTPHeaderField: "Upload-Offset")
    #expect(patch1Offset == "0")
    #expect(patch2Offset == "3")
  }

  @Test func emitsProgressEventsPerChunk() async throws {
    tusChunkSize = 3
    defer { tusChunkSize = 6 * 1024 * 1024 }

    let data = Data("hello".utf8)  // 5 bytes → 2 chunks (3 + 2)
    let finalResponse = try makeTUSServerResponseData(path: "f.bin", fullPath: "bucket/f.bin")

    let sc = sequentialClient
    SequentialMockProtocol.responses = [
      // POST: 201 + Location header
      (201, ["Location": locationURL.absoluteString], Data()),
      // PATCH 1 (offset 0, 3 bytes): 204 + Upload-Offset: 3
      (204, ["Upload-Offset": "3"], Data()),
      // PATCH 2 (offset 3, 2 bytes): 200 + final response body
      (200, ["Upload-Offset": "5"], finalResponse),
    ]

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "f.bin",
      source: .data(data),
      options: FileOptions(contentType: "application/octet-stream"),
      client: sc
    )

    var progressFractions: [Double] = []
    for await event in task.events {
      if case .progress(let p) = event {
        progressFractions.append(p.fractionCompleted)
      }
    }

    #expect(progressFractions.count == 2)
    #expect(progressFractions[0] < progressFractions[1])
    #expect(progressFractions[1] == 1.0)
  }

  @Test func cancelMidUploadEmitsCancelledEvent() async throws {
    HangingMockProtocol.resetHang()
    tusChunkSize = 3
    defer { tusChunkSize = 6 * 1024 * 1024 }

    HangingMockProtocol.postResponse = (201, ["Location": locationURL.absoluteString], Data())
    defer { HangingMockProtocol.postResponse = nil }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HangingMockProtocol.self]
    let hangingClient = StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: URLSession(configuration: config)
      )
    )

    let data = Data("hello".utf8)  // 5 bytes, 2 chunks
    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "big.bin",
      source: .data(data),
      options: FileOptions(contentType: "application/octet-stream"),
      client: hangingClient
    )

    // Wait until the first PATCH is actually hanging, then cancel
    Task {
      var iter = HangingMockProtocol.nextPatchHang.makeAsyncIterator()
      _ = await iter.next()
      task.cancel()
    }

    var events: [TransferEvent<FileUploadResponse>] = []
    for await event in task.events { events.append(event) }
    #expect(!events.isEmpty, "stream must emit at least one event before closing")
    if case .failed(let error) = events.last {
      #expect(error.errorCode == .cancelled)
    } else {
      Issue.record(
        "Expected last event .failed(.cancelled), got \(String(describing: events.last))")
    }
  }

  @Test func cancelledTaskResultThrows() async throws {
    HangingMockProtocol.resetHang()
    tusChunkSize = 3
    defer { tusChunkSize = 6 * 1024 * 1024 }

    HangingMockProtocol.postResponse = (201, ["Location": locationURL.absoluteString], Data())
    defer { HangingMockProtocol.postResponse = nil }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HangingMockProtocol.self]
    let hangingClient = StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: URLSession(configuration: config)
      )
    )

    let data = Data("hello".utf8)
    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "big.bin",
      source: .data(data),
      options: FileOptions(contentType: "application/octet-stream"),
      client: hangingClient
    )

    // Wait until the first PATCH is actually hanging, then cancel
    Task {
      var iter = HangingMockProtocol.nextPatchHang.makeAsyncIterator()
      _ = await iter.next()
      task.cancel()
    }

    do {
      _ = try await task.result
      Issue.record("Expected throw")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    }
  }

  @Test func resumeAfterPauseSyncsOffsetViaHEAD() async throws {
    tusChunkSize = 3
    defer { tusChunkSize = 6 * 1024 * 1024 }

    let data = Data("hello".utf8)  // 5 bytes → 2 chunks (3 + 2)
    let finalResponse = try makeTUSServerResponseData(path: "r.txt", fullPath: "bucket/r.txt")

    // POST and PATCH 1 respond immediately; PATCH 2 hangs until we resume
    let sc = sequentialClient
    SequentialMockProtocol.responses = [
      (201, ["Location": locationURL.absoluteString], Data()),
      (204, ["Upload-Offset": "3"], Data()),
    ]
    SequentialMockProtocol.hangWhenExhausted = true

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "r.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain"),
      client: sc
    )

    // Wait until PATCH 2 starts hanging (signals that POST + PATCH 1 are done)
    var iter = SequentialMockProtocol.nextHang.makeAsyncIterator()
    _ = await iter.next()

    task.pause()

    // Wait until the hanging request is actually cancelled (stopLoading called),
    // confirming the pause has fully propagated through the engine actor.
    var cancelIter = SequentialMockProtocol.hangCancelled.makeAsyncIterator()
    _ = await cancelIter.next()

    // Add HEAD (re-sync) and PATCH 2 responses, then resume
    // Disable hang so the engine's new requests are served normally
    SequentialMockProtocol.hangWhenExhausted = false
    SequentialMockProtocol.appendResponse((200, ["Upload-Offset": "3"], Data()))  // HEAD
    SequentialMockProtocol.appendResponse((200, ["Upload-Offset": "5"], finalResponse))  // PATCH 2

    task.resume()

    let response = try await task.result
    #expect(response.path == "r.txt")
    // capturedRequests: POST, PATCH1, hanging-PATCH2 (cancelled), HEAD, PATCH2-real = 5
    // callIndex: POST(0→1) + PATCH1(1→2) + HEAD(2→3) + PATCH2(3→4) = 4
    // (hanging-PATCH2 does NOT advance callIndex)
    let requests = SequentialMockProtocol.capturedRequests
    #expect(requests.count == 5)
    #expect(SequentialMockProtocol.callIndex == 4)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[1].httpMethod == "PATCH")
    #expect(requests[2].httpMethod == "PATCH")  // the hanging-then-cancelled PATCH 2
    #expect(requests[3].httpMethod == "HEAD")  // HEAD re-sync after resume
    #expect(requests[4].httpMethod == "PATCH")  // real PATCH 2 after HEAD
  }

  @Test func resyncesOffsetOn409() async throws {
    let data = Data(repeating: 0x01, count: 100)
    let headCount = LockIsolated(0)

    // POST mock
    Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    ).register()

    let finalResponse = try makeTUSServerResponseData(path: "x.txt", fullPath: "bucket/x.txt")

    // Second PATCH (retry from offset 0 after re-sync) → success
    var patch2 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: finalResponse],
      additionalHeaders: ["Upload-Offset": "100"]
    )

    // HEAD for re-sync — swaps in patch2 on completion
    var headMock = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.head: Data()],
      additionalHeaders: ["Upload-Offset": "0"]
    )
    headMock.onRequestHandler = OnRequestHandler(requestCallback: { _ in
      headCount.withValue { $0 += 1 }
    })
    headMock.completion = {
      patch2.register()
    }
    headMock.register()

    // First PATCH → 409 (triggers HEAD re-sync)
    Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 409,
      data: [.patch: Data()]
    ).register()

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "x.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain"),
      client: client
    )
    let response = try await task.result

    #expect(headCount.value == 1)
    #expect(response.path == "x.txt")
  }
}

// MARK: - SequentialMockProtocol

/// Provides sequential responses for the same URL across multiple requests.
/// Designed for testing PATCH chunk uploads where each call needs a different response.
final class SequentialMockProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responses:
    [(statusCode: Int, headers: [String: String], data: Data)] = []
  private static let lock = NSLock()
  nonisolated(unsafe) static var callIndex = 0
  nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
  private var didFinish = false

  /// When `true`, requests that arrive after all responses are consumed hang
  /// (until cancelled) instead of immediately failing. Use `nextHang` to detect
  /// when a request has entered the hanging state. Use `hangCancelled` to detect
  /// when the hanging request's `stopLoading` has been called (i.e., the pause
  /// has been fully applied by the engine).
  nonisolated(unsafe) static var hangWhenExhausted = false
  nonisolated(unsafe) private static var hangContinuation: AsyncStream<Void>.Continuation?
  nonisolated(unsafe) static var nextHang: AsyncStream<Void> = AsyncStream { _ in }
  nonisolated(unsafe) private static var hangCancelledContinuation: AsyncStream<Void>.Continuation?
  nonisolated(unsafe) static var hangCancelled: AsyncStream<Void> = AsyncStream { _ in }

  static func reset() {
    lock.lock()
    callIndex = 0
    responses = []
    capturedRequests = []
    hangWhenExhausted = false
    let (stream, cont) = AsyncStream<Void>.makeStream()
    nextHang = stream
    hangContinuation = cont
    let (cancelStream, cancelCont) = AsyncStream<Void>.makeStream()
    hangCancelled = cancelStream
    hangCancelledContinuation = cancelCont
    lock.unlock()
  }

  static func appendResponse(_ response: (statusCode: Int, headers: [String: String], data: Data)) {
    lock.lock()
    responses.append(response)
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let index = Self.callIndex
    let shouldHang = Self.hangWhenExhausted && index >= Self.responses.count
    if !shouldHang {
      Self.callIndex += 1
    }
    Self.capturedRequests.append(request)
    Self.lock.unlock()

    if shouldHang {
      Self.hangContinuation?.yield(())
      // Hang — stopLoading() will cancel
      return
    }

    guard index < Self.responses.count else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let resp = Self.responses[index]
    let httpResponse = HTTPURLResponse(
      url: request.url!,
      statusCode: resp.statusCode,
      httpVersion: nil,
      headerFields: resp.headers
    )!
    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: resp.data)
    client?.urlProtocolDidFinishLoading(self)
    didFinish = true
  }

  override func stopLoading() {
    if !didFinish {
      client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
      Self.hangCancelledContinuation?.yield(())
    }
  }
}

// MARK: - HangingMockProtocol

/// Hangs all PATCH/HEAD requests indefinitely (until cancelled). POST requests respond
/// immediately with `postResponse`. Use this to test task cancellation mid-upload.
final class HangingMockProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var postResponse:
    (statusCode: Int, headers: [String: String], data: Data)?

  // Signals when a PATCH/HEAD request starts hanging
  nonisolated(unsafe) private static var patchHangContinuation: AsyncStream<Void>.Continuation?
  nonisolated(unsafe) static var nextPatchHang: AsyncStream<Void> = AsyncStream { _ in }

  static func resetHang() {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    nextPatchHang = stream
    patchHangContinuation = continuation
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if request.httpMethod == "POST", let resp = Self.postResponse {
      let httpResponse = HTTPURLResponse(
        url: request.url!,
        statusCode: resp.statusCode,
        httpVersion: nil,
        headerFields: resp.headers
      )!
      client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: resp.data)
      client?.urlProtocolDidFinishLoading(self)
    } else {
      // Signal that we are hanging
      Self.patchHangContinuation?.yield(())
      // Hang — do NOT call any client? methods until stopLoading is called
    }
  }

  override func stopLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
  }
}
