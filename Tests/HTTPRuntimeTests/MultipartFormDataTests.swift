//
//  MultipartFormDataTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//

import Foundation
import Testing

@testable import HTTPRuntime

@Suite
struct MultipartFormDataTests {

  @Test
  func multipartAssemblesToFileWithoutBufferingSource() throws {
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("src-\(UUID().uuidString).bin")
    let payload = Data((0..<200_000).map { UInt8($0 % 256) })
    try payload.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let form = MultipartFormData(boundary: "TESTBOUNDARY")
      .addText(name: "meta", value: #"{"k":"v"}"#)
      .addFile(
        name: "file", fileURL: sourceURL, fileName: "big.bin", mimeType: "application/octet-stream")

    let bodyURL = try form.buildToTempFile()
    defer { try? FileManager.default.removeItem(at: bodyURL) }
    let body = try Data(contentsOf: bodyURL)

    #expect(form.contentType == "multipart/form-data; boundary=TESTBOUNDARY")
    let text = String(decoding: body.prefix(400), as: UTF8.self)
    #expect(text.contains("--TESTBOUNDARY"))
    #expect(text.contains(#"Content-Disposition: form-data; name="meta""#))
    #expect(text.contains(#"name="file"; filename="big.bin""#))
    #expect(body.count > payload.count)
  }
}
