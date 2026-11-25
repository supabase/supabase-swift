//
//  IcebergSchemaCodingTests.swift
//  StorageIceberg
//
//  Created by Guilherme Souza on 25/11/26.
//

import Foundation
import Helpers
import Testing

@_spi(Experimental) import StorageIceberg

@Suite
struct IcebergSchemaCodingTests {
  @Test
  func aNestedSchemaRoundTrips() throws {
    let json = #"""
      {
        "type": "struct",
        "schema-id": 0,
        "identifier-field-ids": [1],
        "fields": [
          {"id": 1, "name": "id", "required": true, "type": "long"},
          {
            "id": 2, "name": "tags", "required": false,
            "type": {
              "type": "list", "element-id": 4, "element-required": true,
              "element": {
                "type": "struct",
                "fields": [{"id": 5, "name": "label", "required": true, "type": "string"}]
              }
            }
          },
          {
            "id": 3, "name": "counts", "required": false, "doc": "Counts by key.",
            "type": {
              "type": "map", "key-id": 6, "key": "string",
              "value-id": 7, "value": "long", "value-required": false
            }
          }
        ]
      }
      """#

    let schema = try decode(IcebergSchema.self, json)

    #expect(
      schema
        == IcebergSchema(
          schemaID: 0,
          fields: [
            IcebergField(id: 1, name: "id", type: .long, isRequired: true),
            IcebergField(
              id: 2, name: "tags",
              type: .list(
                IcebergListType(
                  elementID: 4,
                  element: .struct([
                    IcebergField(id: 5, name: "label", type: .string, isRequired: true)
                  ]),
                  isElementRequired: true)),
              isRequired: false),
            IcebergField(
              id: 3, name: "counts",
              type: .map(
                IcebergMapType(
                  keyID: 6, key: .string, valueID: 7, value: .long, isValueRequired: false)),
              isRequired: false, doc: "Counts by key."),
          ],
          identifierFieldIDs: [1]))
    #expect(try encoded(schema) == jsonValue(json))
  }

  @Test
  func theSchemaTypeIsAlwaysEncodedAsStruct() throws {
    let schema = try decode(IcebergSchema.self, #"{"fields":[]}"#)

    #expect(schema == IcebergSchema(fields: []))
    #expect(try encoded(schema) == jsonValue(#"{"type":"struct","fields":[]}"#))
  }

  @Test
  func anUnknownTypeIsKeptVerbatim() throws {
    let object = #"{"id":1,"name":"v","required":false,"type":{"type":"variant2","x":1}}"#
    let field = try decode(IcebergField.self, object)

    #expect(field.type == .unknown(["type": "variant2", "x": 1]))
    #expect(try encoded(field) == jsonValue(object))

    let primitive = #"{"id":1,"name":"g","required":false,"type":"geometry(srid:4326)"}"#
    let geometry = try decode(IcebergField.self, primitive)

    #expect(geometry.type == .primitive("geometry(srid:4326)"))
    #expect(try encoded(geometry) == jsonValue(primitive))
  }

  @Test
  func primitiveHelpersSpellTheWireNames() throws {
    #expect(try encoded(IcebergType.decimal(precision: 10, scale: 2)) == "decimal(10, 2)")
    #expect(try encoded(IcebergType.fixed(length: 16)) == "fixed[16]")
    #expect(IcebergPrimitiveType.timestampNs.rawValue == "timestamp_ns")
    #expect(IcebergPrimitiveType.timestamptzNs.rawValue == "timestamptz_ns")
    #expect(IcebergType.timestamptz == .primitive("timestamptz"))
  }

  @Test
  func transformsAndSortValuesRoundTrip() throws {
    #expect(IcebergTransform.bucket(16).rawValue == "bucket[16]")
    #expect(IcebergTransform.truncate(4).rawValue == "truncate[4]")
    #expect(try decode(IcebergTransform.self, #""bucket[16]""#) == .bucket(16))
    #expect(try decode(IcebergTransform.self, #""zorder""#) == IcebergTransform(rawValue: "zorder"))
    #expect(try encoded(IcebergTransform(rawValue: "zorder")) == "zorder")

    let json =
      #"{"source-id":1,"transform":"identity","direction":"asc","null-order":"nulls-first"}"#
    let field = try decode(IcebergSortField.self, json)

    #expect(
      field
        == IcebergSortField(
          sourceID: 1, transform: .identity, direction: .ascending, nullOrder: .nullsFirst))
    #expect(try encoded(field) == jsonValue(json))
  }

  @Test
  func liveSpecAndSortOrderRoundTrip() throws {
    let specJSON =
      #"{"spec-id":0,"fields":[{"name":"id","transform":"identity","source-id":1,"field-id":1000}]}"#
    let spec = try decode(IcebergPartitionSpec.self, specJSON)

    #expect(
      spec
        == IcebergPartitionSpec(
          specID: 0,
          fields: [
            IcebergPartitionField(fieldID: 1000, sourceID: 1, name: "id", transform: .identity)
          ]))
    #expect(try encoded(spec) == jsonValue(specJSON))

    let orderJSON =
      #"{"order-id":1,"fields":[{"transform":"identity","source-id":1,"direction":"desc","null-order":"nulls-last"}]}"#
    let order = try decode(IcebergSortOrder.self, orderJSON)

    #expect(
      order
        == IcebergSortOrder(
          orderID: 1,
          fields: [
            IcebergSortField(
              sourceID: 1, transform: .identity, direction: .descending, nullOrder: .nullsLast)
          ]))
    #expect(try encoded(order) == jsonValue(orderJSON))
  }

  @Test
  func aDecimalMatchesTheFormTheCatalogReturns() throws {
    let field = try decode(
      IcebergField.self, #"{"id":1,"name":"total","required":false,"type":"decimal(10, 2)"}"#)

    #expect(field.type == .decimal(precision: 10, scale: 2))
  }
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
  try JSONDecoder().decode(type, from: Data(json.utf8))
}

private func jsonValue(_ json: String) throws -> JSONValue {
  try decode(JSONValue.self, json)
}

private func encoded(_ value: some Encodable) throws -> JSONValue {
  try decode(JSONValue.self, String(decoding: JSONEncoder().encode(value), as: UTF8.self))
}
