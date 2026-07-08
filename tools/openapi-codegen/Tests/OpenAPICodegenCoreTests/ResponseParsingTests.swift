//
//  ResponseParsingTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct ResponseParsingTests {

  @Test
  func parsesSuccessAndErrorResponses() throws {
    let json = """
      {
        "200": {
          "description": "ok",
          "content": {"application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}}
        },
        "404": {
          "description": "not found",
          "content": {"application/json": {"schema": {"$ref": "#/components/schemas/errorSchema"}}}
        }
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let (irResponses, hoisted) = try OpenAPIParsing.parseResponses(responses, location: "getBucket")

    #expect(irResponses.count == 2)
    #expect(irResponses[0].statusCode == 200)
    #expect(irResponses[0].isError == false)
    #expect(irResponses[0].body == .json(.schemaRef("bucketSchema")))
    #expect(irResponses[1].statusCode == 404)
    #expect(irResponses[1].isError == true)
    #expect(irResponses[1].body == .json(.schemaRef("errorSchema")))
    #expect(hoisted.isEmpty)
  }

  @Test
  func parsesBinaryResponseBody() throws {
    let json = """
      {
        "200": {
          "description": "ok",
          "content": {"application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}
        }
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let (irResponses, hoisted) = try OpenAPIParsing.parseResponses(responses, location: "download")

    #expect(irResponses[0].body == .binary)
    #expect(hoisted.isEmpty)
  }

  @Test
  func skipsDefaultAndRangeStatusEntries() throws {
    let json = """
      {
        "200": {"description": "ok", "content": {}},
        "default": {"description": "generic error", "content": {}}
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let (irResponses, hoisted) = try OpenAPIParsing.parseResponses(responses, location: "op")

    #expect(irResponses.count == 1)
    #expect(irResponses[0].statusCode == 200)
    #expect(hoisted.isEmpty)
  }

  @Test
  func hoistsInlineObjectResponseBody() throws {
    let json = """
      {
        "200": {
          "description": "ok",
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "key": {"type": "string"},
                  "metadata": {
                    "type": "object",
                    "properties": {"cacheControl": {"type": "string"}}
                  }
                }
              }
            }
          }
        }
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let (irResponses, hoisted) = try OpenAPIParsing.parseResponses(
      responses, location: "copyObject")

    #expect(irResponses[0].body == .json(.schemaRef("copyObject_response200")))
    #expect(hoisted.count == 2)
    #expect(hoisted[0].name == "copyObject_response200")
    #expect(hoisted[1].name == "copyObject_response200_metadata")
  }

  @Test
  func hoistsArrayOfInlineObjectResponseBody() throws {
    let json = """
      {
        "application/json": {
          "schema": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {"path": {"type": "string"}}
            }
          }
        }
      }
      """
    let content = try JSONDecoder().decode(OpenAPI.Content.Map.self, from: Data(json.utf8))

    let (body, hoisted) = try OpenAPIParsing.parseResponseBody(
      content, operationId: "objectSignMany", statusCode: 200, location: "objectSignMany -> 200")

    #expect(body == .json(.array(.schemaRef("objectSignMany_response200Item"))))
    #expect(hoisted.count == 1)
    #expect(hoisted[0].name == "objectSignMany_response200Item")
  }

  @Test
  func parsesFullDocumentEndToEnd() throws {
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
                }
              }
            }
          }
        },
        "components": {
          "schemas": {
            "bucketSchema": {
              "type": "object",
              "required": ["id"],
              "properties": {"id": {"type": "string"}}
            }
          }
        }
      }
      """
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: Data(json.utf8))

    let irDocument = try OpenAPIParsing.parseDocument(document)

    #expect(irDocument.schemas.map(\.name) == ["bucketSchema"])
    #expect(irDocument.operations.count == 1)
    #expect(irDocument.operations[0].operationId == "getBucket")
    #expect(irDocument.operations[0].method == .get)
    #expect(irDocument.operations[0].path == "/bucket/{bucketId}")
  }

  @Test
  func skipsOperationsWithoutAnOperationId() throws {
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
              "responses": {"200": {"description": "ok", "content": {}}}
            }
          },
          "/metrics": {
            "get": {
              "responses": {"200": {"description": "ok", "content": {}}}
            }
          }
        },
        "components": {"schemas": {}}
      }
      """
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: Data(json.utf8))

    let irDocument = try OpenAPIParsing.parseDocument(document)

    #expect(irDocument.operations.count == 1)
    #expect(irDocument.operations[0].operationId == "getBucket")
  }
}
