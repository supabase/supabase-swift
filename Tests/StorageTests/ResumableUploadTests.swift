import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@_spi(Experimental) @testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct ResumableUploadTests {
  private final class Script: Sendable {
    typealias Step = @Sendable (HTTPRequest, Data) async throws -> (HTTPResponse, Data)

    let steps: LockIsolated<[Step]>
    let log = LockIsolated<[String]>([])

    init(_ steps: [Step]) {
      self.steps = LockIsolated(steps)
    }

    func send(_ request: HTTPRequest, body: HTTPBody?) async throws -> (HTTPResponse, HTTPBody?) {
      let data = if let body { try await Data(collecting: body, upTo: .max) } else { Data() }
      var line = "\(request.method.rawValue) \(request.path ?? "")"
      if let offset = request.headerFields[.uploadOffset] { line += " @\(offset)" }
      if !data.isEmpty { line += " +\(data.count)" }
      let entry = line
      log.withValue { $0.append(entry) }
      let step = steps.withValue { $0.isEmpty ? nil : $0.removeFirst() }
      guard let step else { throw URLError(.badServerResponse) }
      let (response, responseBody) = try await step(request, data)
      return (response, responseBody.isEmpty ? nil : HTTPBody(responseBody))
    }
  }

  private static func created(offset: Int64) -> Script.Step {
    { _, _ in
      (
        HTTPResponse(
          status: .created,
          headerFields: [.location: "/storage/v1/upload/resumable/abc", .uploadOffset: "\(offset)"]),
        Data()
      )
    }
  }

  private static func appended(offset: Int64, complete: Bool = false) -> Script.Step {
    { _, _ in
      var headers: HTTPFields = [.uploadOffset: "\(offset)"]
      if complete { headers[.tusComplete] = "1" }
      return (
        HTTPResponse(status: .noContent, headerFields: headers),
        complete
          ? Data(#"{"Key":"bucket/video.mp4","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}"#.utf8)
          : Data()
      )
    }
  }

  private static func head(offset: Int64) -> Script.Step {
    { _, _ in (HTTPResponse(status: .ok, headerFields: [.uploadOffset: "\(offset)"]), Data()) }
  }

  private static func status(_ code: Int) -> Script.Step {
    { _, _ in
      (
        HTTPResponse(status: .init(code: code), headerFields: [.contentType: "text/plain"]),
        Data("nope".utf8)
      )
    }
  }

  private static let transportFailure: Script.Step = { _, _ in
    throw URLError(.networkConnectionLost)
  }

  private let root: URL
  private let fileURL: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    fileURL = root.appendingPathComponent("video.mp4")
    try Data((0..<20).map(UInt8.init)).write(to: fileURL)
  }

  private func makeBucket(_ script: Script, retryTimeout: Duration = .seconds(60)) -> StorageBucket
  {
    var configuration = StorageClientConfiguration(
      url: URL(string: "http://localhost:54321/storage/v1")!,
      headers: [:],
      http: .init(transport: ClosureTransport { try await script.send($0, body: $1) }))
    configuration.resumable = ResumableUploadConfiguration(
      chunkSize: 8, retryTimeout: retryTimeout, directory: root.appendingPathComponent("store"))
    configuration.clock = ImmediateClock()
    return StorageClient(configuration: configuration).from("bucket")
  }

  private var store: ResumableStore {
    ResumableStore(directory: root.appendingPathComponent("store"))
  }

  @Test
  func startCreatesThenAppendsEveryChunkAndCompletes() async throws {
    let script = Script([
      Self.created(offset: 0), Self.appended(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)
    let progress = upload.progress
    let states = upload.states

    #expect(upload.totalBytes == 20)
    #expect(upload.bucketId == "bucket")
    #expect(upload.path == "video.mp4")
    try await upload.start()
    let object = try await upload.result

    #expect(
      object
        == UploadedObject(
          id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"), path: "video.mp4",
          fullPath: "bucket/video.mp4"))
    #expect(
      script.log.value == [
        "POST /storage/v1/upload/resumable",
        "PATCH /storage/v1/upload/resumable/abc @0 +8",
        "PATCH /storage/v1/upload/resumable/abc @8 +8",
        "PATCH /storage/v1/upload/resumable/abc @16 +4",
      ])
    var completed: [Int64] = []
    for await p in progress {
      completed.append(p.completedBytes); if p.completedBytes == 20 { break }
    }
    #expect(completed.last == 20, "a late reader gets the newest value, as the stream buffers one")
    #expect(completed == completed.sorted())
    var seen: [String] = []
    for await state in states {
      seen.append(state.name)
      if case .completed = state { break }
    }
    #expect(seen == ["uploading", "completed"])
    #expect(try store.records().isEmpty)
    guard case .completed(let final) = await upload.state else {
      Issue.record("not completed"); return
    }
    #expect(final == object)
  }

  @Test
  func startThrowsWhenTheServerRejectsTheCreation() async throws {
    let upload = try makeBucket(Script([Self.status(413)])).resumableUpload(
      path: "video.mp4", fileURL: fileURL)

    let error = await #expect(throws: StorageError.self) { try await upload.start() }

    #expect(error?.code == StorageError.Code.entityTooLarge)
    guard case .failed = await upload.state else { Issue.record("not failed"); return }
    await #expect(throws: StorageError.self) { try await upload.result }
  }

  @Test
  func offsetConflictResyncsWithHead() async throws {
    let script = Script([
      Self.created(offset: 0), Self.status(409), Self.head(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    try await upload.start()
    _ = try await upload.result

    #expect(
      script.log.value.dropFirst() == [
        "PATCH /storage/v1/upload/resumable/abc @0 +8",
        "HEAD /storage/v1/upload/resumable/abc",
        "PATCH /storage/v1/upload/resumable/abc @8 +8",
        "PATCH /storage/v1/upload/resumable/abc @16 +4",
      ])
  }

  @Test
  func goneUploadIsCreatedAgain() async throws {
    let script = Script([
      Self.created(offset: 0), Self.appended(offset: 8), Self.status(404), Self.created(offset: 0),
      Self.appended(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    try await upload.start()
    _ = try await upload.result

    #expect(
      script.log.value[2...4] == [
        "PATCH /storage/v1/upload/resumable/abc @8 +8",
        "POST /storage/v1/upload/resumable",
        "PATCH /storage/v1/upload/resumable/abc @0 +8",
      ])
  }

  @Test
  func transportFailuresRetryAfterAHeadUntilTheBudgetIsSpent() async throws {
    let script = Script([
      Self.created(offset: 0), Self.transportFailure, Self.head(offset: 0), Self.transportFailure,
      Self.head(offset: 0), Self.appended(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    try await upload.start()
    _ = try await upload.result

    #expect(script.log.value.count == 8)

    let exhausted = Script(
      [Self.created(offset: 0)] + Array(repeating: Self.transportFailure, count: 100))
    let failing = try makeBucket(exhausted, retryTimeout: .seconds(5)).resumableUpload(
      path: "video.mp4", fileURL: fileURL)
    try await failing.start()
    let error = await #expect(throws: StorageError.self) { try await failing.result }
    #expect(error?.kind == .transport)
    #expect(exhausted.steps.value.count > 50)
    #expect(
      try store.records().count == 1,
      "the record survives a transport failure so a relaunch can resume it")
  }

  @Test
  func serverErrorsFailWithoutRetry() async throws {
    let script = Script([Self.created(offset: 0), Self.status(413)])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    try await upload.start()
    let error = await #expect(throws: StorageError.self) { try await upload.result }

    #expect(error?.code == StorageError.Code.entityTooLarge)
    #expect(script.log.value.count == 2)
    #expect(try store.records().isEmpty)
  }

  @Test
  func pauseStopsAfterTheInFlightChunkAndResumeContinuesFromTheServerOffset() async throws {
    let (gate, open) = AsyncStream<Void>.makeStream()
    let script = Script([
      Self.created(offset: 0),
      { request, data in
        for await _ in gate { break }
        return try await Self.appended(offset: 8)(request, data)
      },
      Self.head(offset: 8), Self.appended(offset: 16), Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await upload.start()
    while script.log.value.count < 2 { await Task.yield() }

    await upload.pause()
    guard case .paused = await upload.state else { Issue.record("not paused"); return }
    open.yield()
    while await upload.isRunning { await Task.yield() }
    #expect(script.log.value.count == 2)
    #expect(try store.record(fingerprint: upload.id.rawValue)?.lastKnownOffset == 8)

    try await upload.resume()
    _ = try await upload.result

    #expect(
      script.log.value.dropFirst(2) == [
        "HEAD /storage/v1/upload/resumable/abc",
        "PATCH /storage/v1/upload/resumable/abc @8 +8",
        "PATCH /storage/v1/upload/resumable/abc @16 +4",
      ])
  }

  @Test
  func cancelTerminatesOnTheServerAndRemovesTheRecord() async throws {
    let (gate, _) = AsyncStream<Void>.makeStream()
    let script = Script([
      Self.created(offset: 0),
      { _, _ in
        for await _ in gate {}
        throw CancellationError()
      },
      { _, _ in (HTTPResponse(status: .noContent), Data()) },
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await upload.start()
    while script.log.value.count < 2 { await Task.yield() }

    await upload.cancel()

    guard case .cancelled = await upload.state else { Issue.record("not cancelled"); return }
    #expect(script.log.value.last == "DELETE /storage/v1/upload/resumable/abc")
    #expect(try store.records().isEmpty)
    await #expect(throws: CancellationError.self) { try await upload.result }
  }

  @Test
  func aSecondUploadOverTheSameStoreContinuesFromTheRecord() async throws {
    let first = Script([Self.created(offset: 0), Self.appended(offset: 8), Self.transportFailure])
    let upload = try makeBucket(first, retryTimeout: .zero).resumableUpload(
      path: "video.mp4", fileURL: fileURL)
    try await upload.start()
    await #expect(throws: StorageError.self) { try await upload.result }

    let second = Script([
      Self.head(offset: 8), Self.appended(offset: 16), Self.appended(offset: 20, complete: true),
    ])
    let relaunched = try makeBucket(second).resumableUpload(path: "video.mp4", fileURL: fileURL)
    #expect(relaunched.id == upload.id)
    try await relaunched.start()
    _ = try await relaunched.result

    #expect(second.log.value.first == "HEAD /storage/v1/upload/resumable/abc")
    #expect(try store.records().isEmpty)
  }

  @Test
  func cancellingAnObserverLeavesTheUploadRunning() async throws {
    let (gate, open) = AsyncStream<Void>.makeStream()
    let script = Script([
      Self.created(offset: 0),
      { request, data in
        for await _ in gate { break }
        return try await Self.appended(offset: 8)(request, data)
      },
      Self.appended(offset: 16), Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)
    try await upload.start()
    let observer = Task { try await upload.result }
    while script.log.value.count < 2 { await Task.yield() }

    observer.cancel()
    await #expect(throws: CancellationError.self) { try await observer.value }
    open.yield()
    _ = try await upload.result

    #expect(script.log.value.count == 4)
  }

  @Test
  func dataIsSpooledIntoTheStore() async throws {
    let script = Script([Self.created(offset: 0), Self.appended(offset: 3, complete: true)])
    let upload = try makeBucket(script).resumableUpload(path: "small.bin", data: Data("abc".utf8))

    try await upload.start()
    _ = try await upload.result

    #expect(upload.totalBytes == 3)
    #expect(script.log.value.last == "PATCH /storage/v1/upload/resumable/abc @0 +3")
    #expect(try store.records().isEmpty)
  }

  @Test
  func concurrentStartsCreateOneUpload() async throws {
    let script = Script([
      { request, body in
        try await Task.sleep(for: .milliseconds(50))
        return try await Self.created(offset: 0)(request, body)
      },
      Self.appended(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    async let first: Void = upload.start()
    async let second: Void = upload.start()
    _ = try await (first, second)
    _ = try await upload.result

    #expect(script.log.value.filter { $0.hasPrefix("POST") }.count == 1)
  }

  @Test
  func startTwiceIsANoOp() async throws {
    let script = Script([
      Self.created(offset: 0), Self.appended(offset: 8), Self.appended(offset: 16),
      Self.appended(offset: 20, complete: true),
    ])
    let upload = try makeBucket(script).resumableUpload(path: "video.mp4", fileURL: fileURL)

    try await upload.start()
    try await upload.start()
    _ = try await upload.result

    #expect(script.log.value.filter { $0.hasPrefix("POST") }.count == 1)
  }
}

extension ResumableUpload.State {
  fileprivate var name: String {
    switch self {
    case .pending: "pending"
    case .uploading: "uploading"
    case .paused: "paused"
    case .completed: "completed"
    case .failed: "failed"
    case .cancelled: "cancelled"
    }
  }
}
