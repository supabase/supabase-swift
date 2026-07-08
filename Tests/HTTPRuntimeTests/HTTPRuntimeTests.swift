//
//  HTTPRuntimeTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import Testing

@testable import HTTPRuntime

@Suite
struct HTTPRuntimeTests {

  @Test
  func serverSentEventParsing() async throws {
    let raw = """
      event: message
      data: {"delta":"hello"}

      event: progress
      data: {"percent":50}

      event: done
      data: {"total":3}


      """
    let bytes = AsyncThrowingStream<Data, any Error> { continuation in
      let full = Array(Data(raw.utf8))
      let mid = full.count / 2
      continuation.yield(Data(full[0..<mid]))
      continuation.yield(Data(full[mid...]))
      continuation.finish()
    }
    var events: [ServerSentEvent] = []
    for try await event in bytes.serverSentEvents() { events.append(event) }
    #expect(events.count == 3)
    #expect(events[0].event == "message")
    #expect(events[0].data == #"{"delta":"hello"}"#)
    #expect(events[1].event == "progress")
    #expect(events[2].event == "done")
  }

  @Test
  func serverSentEventMultiLineData() async throws {
    let raw = "data: line1\ndata: line2\n\n"
    let bytes = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.yield(Data(raw.utf8))
      continuation.finish()
    }
    var events: [ServerSentEvent] = []
    for try await event in bytes.serverSentEvents() { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "line1\nline2")
  }

  @Test
  func multipartAssemblesToFileWithoutBufferingSource() throws {
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("src-\(UUID().uuidString).bin")
    let payload = Data((0..<200_000).map { UInt8($0 % 256) })
    try payload.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    var form = MultipartFormData(boundary: "TESTBOUNDARY")
    form.append(.init(name: "meta", source: .data(Data(#"{"k":"v"}"#.utf8))))
    form.append(
      .init(
        name: "file", filename: "big.bin", contentType: "application/octet-stream",
        source: .file(sourceURL)))

    let bodyURL = try form.writeToTemporaryFile()
    defer { try? FileManager.default.removeItem(at: bodyURL) }
    let body = try Data(contentsOf: bodyURL)

    #expect(form.contentType == "multipart/form-data; boundary=TESTBOUNDARY")
    let text = String(decoding: body.prefix(400), as: UTF8.self)
    #expect(text.contains("--TESTBOUNDARY"))
    #expect(text.contains(#"Content-Disposition: form-data; name="meta""#))
    #expect(text.contains(#"name="file"; filename="big.bin""#))
    #expect(body.count > payload.count)
  }

  @Test
  func pathEncoding() {
    #expect(PathEncoding.segment("a/b c") == "a%2Fb%20c")
    #expect(PathEncoding.greedy("a/b/c.txt") == "a/b/c.txt")
    #expect(PathEncoding.greedy("a/b c.txt") == "a/b%20c.txt")
  }

  @Test
  func jsonValueRoundTrip() throws {
    let value = JSONValue.object([
      "s": .string("x"),
      "n": .number(3.5),
      "b": .bool(true),
      "arr": .array([.number(1), .null]),
    ])
    let data = try JSONCoding.encoder.encode(value)
    let decoded = try JSONCoding.decoder.decode(JSONValue.self, from: data)
    #expect(decoded == value)
  }

  @Test
  func iso8601DateCoding() throws {
    struct Holder: Codable, Equatable { let at: Date }
    let json = #"{"at":"2026-07-06T12:34:56.789Z"}"#
    let decoded = try JSONCoding.decoder.decode(Holder.self, from: Data(json.utf8))
    let reencoded = try JSONCoding.encoder.encode(decoded)
    let round = try JSONCoding.decoder.decode(Holder.self, from: reencoded)
    #expect(decoded == round)
  }
}
