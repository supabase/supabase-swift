//
//  EndToEndTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct EndToEndTests {

  @Test
  func generatesModelsAndClientFromAMinimalStorageLikeSpec() throws {
    let json = """
      {
        "openapi": "3.0.3",
        "info": {"title": "Storage", "version": "1.0.0"},
        "paths": {
          "/bucket/{bucketId}": {
            "get": {
              "operationId": "getBucket",
              "parameters": [
                {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
              ],
              "responses": {
                "200": {
                  "description": "ok",
                  "content": {
                    "application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}
                  }
                },
                "404": {
                  "description": "not found",
                  "content": {
                    "application/json": {"schema": {"$ref": "#/components/schemas/errorSchema"}}
                  }
                }
              }
            }
          }
        },
        "components": {
          "schemas": {
            "bucketSchema": {
              "type": "object",
              "required": ["id", "public"],
              "properties": {
                "id": {"type": "string"},
                "public": {"type": "boolean"}
              }
            },
            "errorSchema": {
              "type": "object",
              "required": ["message"],
              "properties": {"message": {"type": "string"}}
            }
          }
        }
      }
      """
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: Data(json.utf8))
    let irDocument = try OpenAPIParsing.parseDocument(document)

    let models = SwiftEmitter.emitModels(irDocument)
    let client = SwiftEmitter.emitClient(irDocument, clientName: "StorageOpenAPIClient")

    #expect(models.contains("public struct BucketSchema: Codable, Sendable, Hashable {"))
    #expect(models.contains("public var `public`: Bool"))
    #expect(models.contains("public struct ErrorSchema: Codable, Sendable, Hashable, APIError {"))
    #expect(
      client.contains("public func getBucket(bucketId: String) async throws -> BucketSchema {"))
    #expect(client.contains("errorTypes: [404: ErrorSchema.self]"))
  }
}
