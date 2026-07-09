//
//  ParameterParsingTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct ParameterParsingTests {

  private func parameter(_ json: String) throws -> Either<
    JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter
  > {
    let param = try JSONDecoder().decode(OpenAPI.Parameter.self, from: Data(json.utf8))
    return .b(param)
  }

  @Test
  func parsesRequiredPathParameter() throws {
    let json = """
      {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
      """
    let (irParameter, hoisted) = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.name == "bucketId")
    #expect(irParameter.location == .path)
    #expect(irParameter.type == .string)
    #expect(irParameter.isOptional == false)
    #expect(hoisted.isEmpty)
  }

  @Test
  func parsesOptionalQueryParameter() throws {
    let json = """
      {"name": "limit", "in": "query", "schema": {"type": "integer"}}
      """
    let (irParameter, hoisted) = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .query)
    #expect(irParameter.type == .integer)
    #expect(irParameter.isOptional == true)
    #expect(hoisted.isEmpty)
  }

  @Test
  func parsesHeaderParameter() throws {
    let json = """
      {"name": "if-none-match", "in": "header", "schema": {"type": "string"}}
      """
    let (irParameter, hoisted) = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .header)
    #expect(hoisted.isEmpty)
  }

  @Test
  func rejectsCookieParameter() throws {
    let json = """
      {"name": "session", "in": "cookie", "schema": {"type": "string"}}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseParameter(try parameter(json), location: "op")
    }
  }

  @Test
  func hoistsInlineEnumParameterIntoItsOwnNamedSchema() throws {
    let json = """
      {"name": "resize", "in": "query", "schema": {"type": "string", "enum": ["cover", "contain", "fill"]}}
      """
    let (irParameter, hoisted) = try OpenAPIParsing.parseParameter(
      parameter(json), location: "renderImagePublic")

    #expect(irParameter.name == "resize")
    #expect(irParameter.type == .schemaRef("renderImagePublic_resize"))
    #expect(hoisted.count == 1)
    #expect(hoisted.first?.name == "renderImagePublic_resize")
    #expect(hoisted.first?.kind == .stringEnum(cases: ["cover", "contain", "fill"]))
  }

  @Test
  func hoistsArrayOfInlineObjectParameterIntoItsOwnNamedSchema() throws {
    let json = """
      {
        "name": "paths",
        "in": "query",
        "schema": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {"path": {"type": "string"}}
          }
        }
      }
      """
    let (irParameter, hoisted) = try OpenAPIParsing.parseParameter(
      parameter(json), location: "listObjects")

    #expect(irParameter.name == "paths")
    #expect(irParameter.type == .array(.schemaRef("listObjects_pathsItem")))
    #expect(hoisted.count == 1)
    #expect(hoisted.first?.name == "listObjects_pathsItem")
  }

  @Test
  func rejectsUnionParameter() throws {
    let json = """
      {
        "name": "filter",
        "in": "query",
        "schema": {"anyOf": [{"type": "integer"}, {"type": "string"}]}
      }
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseParameter(try parameter(json), location: "op")
    }
  }
}
