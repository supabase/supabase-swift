//
//  UnionParsingTests.swift
//

import Foundation
import OpenAPIKit
import Testing

@testable import OpenAPICodegenCore

@Suite
struct UnionParsingTests {

  @Test
  func hoistsAnyOfWithScalarBranchesFromAnObjectProperty() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "fileSizeLimit": {
            "anyOf": [
              {"type": "integer", "nullable": true},
              {"type": "string", "nullable": true}
            ]
          }
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "bucketCreate", schema: schema)

    #expect(irSchemas.count == 2)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected the first schema to be the object")
      return
    }
    #expect(properties[0].type == .schemaRef("bucketCreate_fileSizeLimit"))
    #expect(irSchemas[1].name == "bucketCreate_fileSizeLimit")
    #expect(
      irSchemas[1].kind
        == .union(cases: [
          IRUnionCase(name: "integer", type: .integer),
          IRUnionCase(name: "string", type: .string),
        ]))
  }

  @Test
  func rejectsUnionBranchThatIsItselfUnsupported() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "value": {
            "anyOf": [
              {"type": "integer"},
              {"type": "object", "properties": {"nested": {"type": "string"}}}
            ]
          }
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)
    }
  }

  @Test
  func collapsesAnyOfWithNullBranchToPlainNullableProperty() throws {
    let json = """
      {
        "type": "object",
        "required": ["name"],
        "properties": {
          "name": {"anyOf": [{"type": "string"}, {"type": "null"}]}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    // Nullable idiom, not a union: no hoisted schema, plain `String?`.
    #expect(irSchemas.count == 1)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected an object schema")
      return
    }
    #expect(properties[0].name == "name")
    #expect(properties[0].type == .string)
    // `name` is required, so optionality must come from the null branch.
    #expect(properties[0].isOptional == true)
  }

  @Test
  func collapsesAnyOfWithLeadingNullBranchToPlainNullableProperty() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "name": {"anyOf": [{"type": "null"}, {"type": "string"}]}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    #expect(irSchemas.count == 1)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected an object schema")
      return
    }
    #expect(properties[0].type == .string)
  }

  @Test
  func collapsesAnyOfWithNullBranchAndFreeformObjectToPlainFreeform() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "meta": {
            "anyOf": [{"type": "object", "additionalProperties": true}, {"type": "null"}]
          }
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    #expect(irSchemas.count == 1)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected an object schema")
      return
    }
    #expect(properties[0].name == "meta")
    #expect(properties[0].type == .freeform)
  }

  @Test
  func stillHoistsGenuineMultiTypeUnionWithoutNullBranch() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "value": {"anyOf": [{"type": "integer"}, {"type": "string"}]}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    #expect(irSchemas.count == 2)
    #expect(
      irSchemas[0].kind
        == .object(properties: [
          IRProperty(name: "value", type: .schemaRef("widget_value"), isOptional: true)
        ]))
    #expect(
      irSchemas[1].kind
        == .union(cases: [
          IRUnionCase(name: "integer", type: .integer),
          IRUnionCase(name: "string", type: .string),
        ]))
  }

  @Test
  func parsesTypeArrayWithNullAsPlainNullableScalar() throws {
    let json = """
      {
        "type": "object",
        "required": ["size"],
        "properties": {
          "size": {"type": ["integer", "null"]}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    #expect(irSchemas.count == 1)
    guard case .object(let properties) = irSchemas[0].kind else {
      Issue.record("expected an object schema")
      return
    }
    #expect(properties[0].name == "size")
    #expect(properties[0].type == .integer)
    #expect(properties[0].isOptional == true)
  }

  @Test
  func disambiguatesCollidingCaseNamesInTheSameUnion() throws {
    let json = """
      {
        "type": "object",
        "properties": {
          "value": {
            "anyOf": [
              {"type": "array", "items": {"type": "string"}},
              {"type": "array", "items": {"type": "integer"}}
            ]
          }
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchemas = try OpenAPIParsing.parseNamedSchema(name: "widget", schema: schema)

    #expect(irSchemas.count == 2)
    #expect(
      irSchemas[1].kind
        == .union(cases: [
          IRUnionCase(name: "array", type: .array(.string)),
          IRUnionCase(name: "array2", type: .array(.integer)),
        ]))
  }
}
