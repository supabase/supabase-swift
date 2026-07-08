//
//  SwiftNamesTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct SwiftNamesTests {

  @Test
  func convertsSnakeCaseToLowerCamelCase() {
    #expect(SwiftNames.propertyName("file_size_limit") == "fileSizeLimit")
    #expect(SwiftNames.propertyName("id") == "id")
  }

  @Test
  func escapesReservedWords() {
    #expect(SwiftNames.propertyName("public") == "`public`")
    #expect(SwiftNames.propertyName("self") == "`self`")
  }

  @Test
  func convertsSchemaNameToUpperCamelCaseTypeName() {
    #expect(SwiftNames.typeName("bucketSchema") == "BucketSchema")
    #expect(SwiftNames.typeName("errorSchema") == "ErrorSchema")
  }

  @Test
  func rendersTypeReferences() {
    #expect(SwiftNames.typeReference(.string, isOptional: false) == "String")
    #expect(SwiftNames.typeReference(.integer, isOptional: true) == "Int?")
    #expect(SwiftNames.typeReference(.array(.string), isOptional: false) == "[String]")
    #expect(
      SwiftNames.typeReference(.schemaRef("bucketSchema"), isOptional: false) == "BucketSchema")
    #expect(SwiftNames.typeReference(.freeform, isOptional: false) == "[String: JSONValue]")
  }
}
