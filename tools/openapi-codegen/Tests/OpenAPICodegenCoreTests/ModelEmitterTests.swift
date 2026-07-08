//
//  ModelEmitterTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct ModelEmitterTests {

  @Test
  func emitsStructWithCodingKeys() {
    let document = IRDocument(
      schemas: [
        IRSchema(
          name: "bucketSchema",
          kind: .object(properties: [
            IRProperty(name: "id", type: .string, isOptional: false),
            IRProperty(name: "file_size_limit", type: .integer, isOptional: true),
          ])
        )
      ],
      operations: []
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public struct BucketSchema: Codable, Sendable, Hashable {"))
    #expect(output.contains("public var id: String"))
    #expect(output.contains("public var fileSizeLimit: Int?"))
    #expect(output.contains(#"case fileSizeLimit = "file_size_limit""#))
  }

  @Test
  func emitsStringEnum() {
    let document = IRDocument(
      schemas: [IRSchema(name: "visibility", kind: .stringEnum(cases: ["public", "private"]))],
      operations: []
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public enum Visibility: String, Codable, Sendable, Hashable {"))
    #expect(output.contains(#"case `public` = "public""#))
    #expect(output.contains(#"case `private` = "private""#))
  }

  @Test
  func marksSchemasReferencedByErrorResponsesAsAPIError() {
    let document = IRDocument(
      schemas: [
        IRSchema(
          name: "errorSchema",
          kind: .object(properties: [IRProperty(name: "message", type: .string, isOptional: false)])
        )
      ],
      operations: [
        IROperation(
          operationId: "getBucket",
          method: .get,
          path: "/bucket/{id}",
          parameters: [],
          requestBody: nil,
          responses: [
            IRResponse(statusCode: 404, isError: true, body: .json(.schemaRef("errorSchema")))
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public struct ErrorSchema: Codable, Sendable, Hashable, APIError {"))
  }
}
