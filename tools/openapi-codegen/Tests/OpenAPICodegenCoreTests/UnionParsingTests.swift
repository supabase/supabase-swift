//
//  UnionParsingTests.swift
//

import Foundation
import OpenAPIKit30
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
}
