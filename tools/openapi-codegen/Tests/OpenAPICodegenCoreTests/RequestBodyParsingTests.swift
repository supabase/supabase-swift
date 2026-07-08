//
//  RequestBodyParsingTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct RequestBodyParsingTests {

  private func requestBody(_ json: String) throws -> Either<
    JSONReference<OpenAPI.Request>, OpenAPI.Request
  > {
    let request = try JSONDecoder().decode(OpenAPI.Request.self, from: Data(json.utf8))
    return .b(request)
  }

  @Test
  func parsesJSONRequestBody() throws {
    let json = """
      {
        "content": {
          "application/json": {"schema": {"$ref": "#/components/schemas/bucketUpdate"}}
        }
      }
      """
    let (body, hoisted) = try OpenAPIParsing.parseRequestBody(
      requestBody(json), location: "updateBucket")

    #expect(body == .json(.schemaRef("bucketUpdate")))
    #expect(hoisted.isEmpty)
  }

  @Test
  func parsesMultipartRequestBodyWithFileField() throws {
    let json = """
      {
        "content": {
          "multipart/form-data": {
            "schema": {
              "type": "object",
              "properties": {
                "cacheControl": {"type": "string"},
                "": {"type": "string", "format": "binary"}
              }
            }
          }
        }
      }
      """
    let (body, hoisted) = try OpenAPIParsing.parseRequestBody(
      requestBody(json), location: "createObject")

    guard case .multipart(let fields) = body else {
      Issue.record("expected a multipart request body")
      return
    }
    let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
    #expect(byName["cacheControl"]?.isFile == false)
    #expect(byName[""]?.isFile == true)
    #expect(hoisted.isEmpty)
  }

  @Test
  func rejectsUnsupportedContentType() throws {
    let json = """
      {"content": {"text/plain": {"schema": {"type": "string"}}}}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseRequestBody(try requestBody(json), location: "op")
    }
  }

  @Test
  func hoistsInlineObjectRequestBody() throws {
    let json = """
      {
        "content": {
          "application/json": {
            "schema": {
              "type": "object",
              "properties": {
                "sourceKey": {"type": "string"},
                "metadata": {
                  "type": "object",
                  "properties": {"cacheControl": {"type": "string"}}
                }
              }
            }
          }
        }
      }
      """
    let (body, hoisted) = try OpenAPIParsing.parseRequestBody(
      requestBody(json), location: "copyObject")

    #expect(body == .json(.schemaRef("copyObject_requestBody")))
    #expect(hoisted.count == 2)
    #expect(hoisted[0].name == "copyObject_requestBody")
    #expect(hoisted[1].name == "copyObject_requestBody_metadata")
  }

  @Test
  func hoistsArrayOfInlineObjectRequestBody() throws {
    let json = """
      {
        "content": {
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
      }
      """
    let (body, hoisted) = try OpenAPIParsing.parseRequestBody(
      requestBody(json), location: "deleteObjects")

    #expect(body == .json(.array(.schemaRef("deleteObjects_requestBodyItem"))))
    #expect(hoisted.count == 1)
    #expect(hoisted[0].name == "deleteObjects_requestBodyItem")
  }
}
