//
//  TypeParsingTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct TypeParsingTests {

  private func schema(_ json: String) throws -> JSONSchema {
    try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
  }

  @Test
  func parsesArrayOfStrings() throws {
    let type = try OpenAPIParsing.parseType(
      schema(#"{"type": "array", "items": {"type": "string"}}"#), location: "test")
    #expect(type == .array(.string))
  }

  @Test
  func rejectsArrayWithoutItems() throws {
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(#"{"type": "array"}"#), location: "test")
    }
  }

  @Test
  func parsesSchemaReference() throws {
    let type = try OpenAPIParsing.parseType(
      schema("{\"$ref\": \"#/components/schemas/bucketSchema\"}"), location: "test")
    #expect(type == .schemaRef("bucketSchema"))
  }

  @Test
  func parsesFreeformObject() throws {
    let type = try OpenAPIParsing.parseType(schema(#"{"type": "object"}"#), location: "test")
    #expect(type == .freeform)
  }

  @Test
  func rejectsInlineObjectWithProperties() throws {
    let json = #"{"type": "object", "properties": {"a": {"type": "string"}}}"#
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }

  @Test
  func rejectsOneOfUnion() throws {
    let json = """
      {"oneOf": [{"type": "string"}, {"type": "integer"}]}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }

  @Test
  func rejectsInlineEnum() throws {
    let json = #"{"type": "string", "enum": ["a", "b"]}"#
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }
}
