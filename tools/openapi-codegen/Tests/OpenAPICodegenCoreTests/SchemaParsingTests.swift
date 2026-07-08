//
//  SchemaParsingTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct SchemaParsingTests {

  @Test
  func parsesObjectSchemaWithRequiredAndOptionalProperties() throws {
    let json = """
      {
        "type": "object",
        "required": ["id"],
        "properties": {
          "id": {"type": "string"},
          "name": {"type": "string", "nullable": true},
          "size": {"type": "integer"}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widgetSchema", schema: schema)

    #expect(irSchemas.count == 1)
    let irSchema = irSchemas[0]
    #expect(irSchema.name == "widgetSchema")
    guard case .object(let properties) = irSchema.kind else {
      Issue.record("expected an object schema")
      return
    }
    let byName = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
    #expect(byName["id"]?.type == .string)
    #expect(byName["id"]?.isOptional == false)
    #expect(byName["name"]?.isOptional == true)
    #expect(byName["size"]?.type == .integer)
    #expect(byName["size"]?.isOptional == true)
  }

  @Test
  func parsesStringEnumSchema() throws {
    let json = """
      {"type": "string", "enum": ["public", "private"]}
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "visibility", schema: schema)

    #expect(irSchemas.count == 1)
    let irSchema = irSchemas[0]
    #expect(irSchema.name == "visibility")
    #expect(irSchema.kind == .stringEnum(cases: ["public", "private"]))
  }

  @Test
  func rejectsNonObjectNonEnumTopLevelSchema() throws {
    let json = #"{"type": "integer"}"#
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseNamedSchema(name: "count", schema: schema)
    }
  }

  @Test
  func hoistsInlineEnumPropertyIntoItsOwnNamedSchema() throws {
    let json = """
      {
        "type": "object",
        "required": ["id", "type"],
        "properties": {
          "id": {"type": "string"},
          "type": {"type": "string", "enum": ["STANDARD", "ANALYTICS"]}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "bucketSchema", schema: schema)

    #expect(irSchemas.count == 2)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected the first schema to be the object")
      return
    }
    let byName = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
    #expect(byName["type"]?.type == .schemaRef("bucketSchema_type"))
    #expect(irSchemas[1].name == "bucketSchema_type")
    #expect(irSchemas[1].kind == .stringEnum(cases: ["STANDARD", "ANALYTICS"]))
  }
}
