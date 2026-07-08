//
//  ClientEmitterTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct ClientEmitterTests {

  @Test
  func emitsJSONRoundTripOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "getBucket",
          method: .get,
          path: "/bucket/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: nil,
          responses: [
            IRResponse(statusCode: 200, isError: false, body: .json(.schemaRef("bucketSchema"))),
            IRResponse(statusCode: 404, isError: true, body: .json(.schemaRef("errorSchema"))),
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("public struct StorageOpenAPIClient: Sendable {"))
    #expect(output.contains("public func getBucket(bucketId: String) async throws -> BucketSchema {"))
    #expect(
      output.contains(
        "HTTPRequestBuilder(method: .get, baseURL: baseURL, path: \"/bucket/\\(PathEncoding.segment(bucketId))\")"
      ))
    #expect(output.contains("try response.checkStatus(errorTypes: [404: ErrorSchema.self])"))
    #expect(output.contains("return try JSONCoding.decoder.decode(BucketSchema.self, from: response.body)"))
  }

  @Test
  func emitsMultipartUploadOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "createObject",
          method: .post,
          path: "/object/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: .multipart(fields: [
            IRMultipartField(name: "file", type: .string, isFile: true),
            IRMultipartField(name: "cacheControl", type: .string, isFile: false),
          ]),
          responses: [
            IRResponse(statusCode: 200, isError: false, body: .none)
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("file: URL"))
    #expect(output.contains("cacheControl: String"))
    #expect(output.contains("source: .file(file)"))
    #expect(output.contains("builder.setBody(.multipart(formData))"))
  }

  @Test
  func emitsBinaryDownloadOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "download",
          method: .get,
          path: "/object/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: nil,
          responses: [IRResponse(statusCode: 200, isError: false, body: .binary)]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("-> AsyncThrowingStream<Data, any Error> {"))
    #expect(output.contains("transport.stream(try builder.build())"))
  }
}
