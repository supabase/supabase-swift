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
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.name == "bucketId")
    #expect(irParameter.location == .path)
    #expect(irParameter.type == .string)
    #expect(irParameter.isOptional == false)
  }

  @Test
  func parsesOptionalQueryParameter() throws {
    let json = """
      {"name": "limit", "in": "query", "schema": {"type": "integer"}}
      """
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .query)
    #expect(irParameter.type == .integer)
    #expect(irParameter.isOptional == true)
  }

  @Test
  func parsesHeaderParameter() throws {
    let json = """
      {"name": "if-none-match", "in": "header", "schema": {"type": "string"}}
      """
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .header)
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
}
