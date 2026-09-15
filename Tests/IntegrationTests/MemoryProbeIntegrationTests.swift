//
//  MemoryProbeIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 14/09/26.
//
//  Live probe: how much memory each upload/download shape costs on top of the process baseline.
//  One scenario per process, so freed-but-still-resident pages from an earlier scenario cannot
//  hide the cost of a later one:
//
//    INTEGRATION_TESTS=1 MEMORY_PROBE=1 MEMORY_PROBE_SCENARIO=<name> \
//      swift test --no-parallel --filter MemoryProbe
//
//  Results are printed, not asserted.
//

#if canImport(Darwin)
  import Darwin
  import Foundation
  import HTTPTypes
  import HTTPTypesFoundation
  import Helpers
  import Testing

  @testable import Storage

  private let megabyte = 1 << 20

  /// Physical footprint of this process, the number Xcode's memory gauge shows.
  private func physicalFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
  }

  private final class PeakBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64
    init(_ value: UInt64) { _value = value }
    var value: UInt64 { lock.withLock { _value } }
    func record(_ sample: UInt64) { lock.withLock { _value = max(_value, sample) } }
  }

  /// Samples the footprint every few milliseconds while `body` runs and reports the peak delta.
  private func measure<T>(
    _ label: String, _ body: @Sendable () async throws -> T
  ) async throws -> T {
    let baseline = physicalFootprint()
    let peak = PeakBox(baseline)
    let sampler = Task.detached {
      while !Task.isCancelled {
        peak.record(physicalFootprint())
        try? await Task.sleep(for: .milliseconds(2))
      }
    }
    let start = ContinuousClock.now
    let result: T
    do {
      result = try await body()
    } catch {
      sampler.cancel()
      print("MEMPROBE | \(label) | FAILED: \(error)")
      throw error
    }
    let elapsed = ContinuousClock.now - start
    sampler.cancel()
    let deltaMB = Double(peak.value) / Double(megabyte) - Double(baseline) / Double(megabyte)
    print(
      String(
        format: "MEMPROBE | %-44@ | baseline %6.1f MB | peak delta %+7.1f MB | %.2f s",
        label as NSString, Double(baseline) / Double(megabyte), deltaMB,
        Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18))
    return result
  }

  @Suite(
    .enabled(
      if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil
        && ProcessInfo.processInfo.environment["MEMORY_PROBE"] != nil),
    .serialized
  )
  struct MemoryProbeIntegrationTests {
    static let fileSizeMB =
      Int(ProcessInfo.processInfo.environment["MEMORY_PROBE_MB"] ?? "") ?? 200
    static let fileSize = fileSizeMB * megabyte
    static let scenario = ProcessInfo.processInfo.environment["MEMORY_PROBE_SCENARIO"]

    let storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
        headers: ["Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"]
      )
    )
    let transport = URLSessionTransport()
    let bucket = "memprobe-\(UUID().uuidString.lowercased())"

    var authHeaders: HTTPFields {
      [
        .authorization: "Bearer \(DotEnv.SUPABASE_SECRET_KEY)",
        .init("apikey")!: DotEnv.SUPABASE_SECRET_KEY,
      ]
    }

    func objectURL(_ path: String) -> URL {
      URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1/object/\(bucket)/\(path)")!
    }

    /// Writes `fileSize` bytes of non-constant content to a temp file without holding it in memory.
    func makeLargeFile() throws -> URL {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "memprobe-\(UUID().uuidString).bin")
      FileManager.default.createFile(atPath: url.path, contents: nil)
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      let chunk = Data((0..<(8 * megabyte)).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761) })
      var written = 0
      while written < Self.fileSize {
        let n = min(chunk.count, Self.fileSize - written)
        try handle.write(contentsOf: chunk.prefix(n))
        written += n
      }
      return url
    }

    func rawSend(_ method: HTTPTypes.HTTPRequest.Method, _ url: URL, body: HTTPBody?)
      async throws -> (HTTPTypes.HTTPResponse, HTTPBody?)
    {
      var headers = authHeaders
      if body != nil { headers[.contentType] = "application/octet-stream" }
      let (head, responseBody) = try await transport.send(
        HTTPTypes.HTTPRequest(method: method, url: url, headerFields: headers), body: body)
      guard (200..<300).contains(head.status.code) else {
        let data = try await Data(collecting: responseBody ?? HTTPBody(Data()), upTo: 1 << 20)
        throw NSError(
          domain: "memprobe", code: head.status.code,
          userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
      }
      return (head, responseBody)
    }

    /// Pull-based file reader: 1 MiB per `next()`, nothing read ahead. A body the SDK cannot rewind.
    struct FileChunks: AsyncSequence, Sendable {
      typealias Element = ArraySlice<UInt8>
      let fileURL: URL
      struct AsyncIterator: AsyncIteratorProtocol {
        let handle: FileHandle
        mutating func next() async throws -> ArraySlice<UInt8>? {
          guard let chunk = try handle.read(upToCount: 1 * megabyte), !chunk.isEmpty else {
            try handle.close()
            return nil
          }
          return ArraySlice(chunk)
        }
      }
      func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(handle: try! FileHandle(forReadingFrom: fileURL))
      }
    }

    func streamedBody(_ fileURL: URL) -> HTTPBody {
      HTTPBody(
        FileChunks(fileURL: fileURL), length: .known(Int64(Self.fileSize)),
        iterationBehavior: .single)
    }

    static let scenarios = [
      "upload-api-data", "upload-api-file", "upload-transport-file", "upload-transport-data",
      "upload-transport-stream", "download-api-data", "download-transport-file",
      "download-transport-data", "download-transport-iterate",
    ]

    @Test(arguments: scenarios)
    func shape(_ name: String) async throws {
      if let only = Self.scenario, only != name { return }

      try await storage.createBucket(bucket)
      let fileURL = try makeLargeFile()
      defer { try? FileManager.default.removeItem(at: fileURL) }

      let needsObject = name.hasPrefix("download")
      if needsObject {
        _ = try await rawSend(.post, objectURL("seed.bin"), body: try HTTPBody(fileURL: fileURL))
      }

      print("MEMPROBE | \(name): file \(Self.fileSizeMB) MB")

      switch name {
      case "upload-api-data":
        // Storage public API, Data → multipart → `formData.encode()` → buffered body.
        // The caller already holds `data`; the delta is what the SDK adds on top of it.
        let data = try Data(contentsOf: fileURL)
        try await measure("storage.upload(data:) multipart") {
          try await storage.from(bucket).upload("o.bin", data: data)
        }
      case "upload-api-file":
        // Storage public API, file URL → multipart → `formData.encode()` reads the file into Data.
        try await measure("storage.upload(fileURL:) multipart") {
          try await storage.from(bucket).upload("o.bin", fileURL: fileURL)
        }
      case "upload-transport-file":
        // HTTPBody(fileURL:) → URLSession.upload(for:fromFile:).
        try await measure("transport POST HTTPBody(fileURL:)") {
          _ = try await rawSend(.post, objectURL("o.bin"), body: try HTTPBody(fileURL: fileURL))
        }
      case "upload-transport-data":
        // HTTPBody(Data) → urlRequest.httpBody. Caller holds `data`; delta is copies on top.
        let data = try Data(contentsOf: fileURL)
        try await measure("transport POST HTTPBody(Data)") {
          _ = try await rawSend(.post, objectURL("o.bin"), body: HTTPBody(data))
        }
      case "upload-transport-stream":
        // Streamed chunks, known length, one-shot → uploadTask(withStreamedRequest:), pulled one
        // chunk at a time as URLSession drains the bound stream pair.
        try await measure("transport POST HTTPBody(stream .known .single)") {
          _ = try await rawSend(.post, objectURL("o.bin"), body: streamedBody(fileURL))
        }
      case "download-api-data":
        // Storage public API → Data.
        let downloaded = try await measure("storage.download(path:) → Data") {
          try await storage.from(bucket).download(path: "seed.bin")
        }
        #expect(downloaded.count == Self.fileSize)
      case "download-transport-file":
        // Response streamed straight to disk.
        let downloadURL = FileManager.default.temporaryDirectory.appendingPathComponent(
          "memprobe-download-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: downloadURL) }
        try await measure("transport GET → HTTPBody.write(to:)") {
          let (_, body) = try await rawSend(.get, objectURL("seed.bin"), body: nil)
          try await body!.write(to: downloadURL)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: downloadURL.path)
        #expect((attrs[.size] as? Int) == Self.fileSize)
      case "download-transport-data":
        // Response collected into Data.
        let collected = try await measure("transport GET → Data(collecting:)") {
          let (_, body) = try await rawSend(.get, objectURL("seed.bin"), body: nil)
          return try await Data(collecting: body!, upTo: Self.fileSize + 1)
        }
        #expect(collected.count == Self.fileSize)
      case "download-transport-iterate":
        // Response iterated chunk by chunk and discarded: the streaming floor.
        let counted = try await measure("transport GET → iterate chunks, discard") {
          let (_, body) = try await rawSend(.get, objectURL("seed.bin"), body: nil)
          var total = 0
          for try await chunk in body! { total += chunk.count }
          return total
        }
        #expect(counted == Self.fileSize)
      default:
        Issue.record("unknown scenario \(name)")
      }

      try await storage.emptyBucket(bucket)
      try await storage.deleteBucket(bucket)
    }
  }
#endif
