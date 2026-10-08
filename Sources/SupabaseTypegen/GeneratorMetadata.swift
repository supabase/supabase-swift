//
//  GeneratorMetadata.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

/// The parts of postgrest-typegen's `GeneratorMetadata` document the generator reads.
///
/// Every collection is flat, as in the document: columns, primary keys and functions point at their
/// relation by id, and ``DatabaseModel`` joins them. Decoded with `.convertFromSnakeCase`.
struct GeneratorMetadata: Decodable {
  var schemas: [Schema]
  var tables: [Relation]
  var views: [View]
  var materializedViews: [Relation]
  var foreignTables: [Relation]
  var columns: [Column]
  var primaryKeys: [PrimaryKey]
  var functions: [Function]
  var types: [PostgresType]

  struct Schema: Decodable {
    var name: String
  }

  struct Relation: Decodable {
    var id: Int
    var schema: String
    var name: String
  }

  struct View: Decodable {
    var id: Int
    var schema: String
    var name: String
    var isUpdatable: Bool
    /// Absent from documents that predate it; falls back to `isUpdatable`.
    var isInsertEnabled: Bool?
    /// Absent from documents that predate it; falls back to `isUpdatable`.
    var isUpdateEnabled: Bool?
  }

  struct Column: Decodable {
    var tableId: Int
    var ordinalPosition: Int
    var name: String
    var format: String
    var typeSchema: String
    /// Whether `default_value` is non-null. The value itself is any JSON and is not read.
    var hasDefault: Bool
    var identityGeneration: IdentityGeneration?
    var isGenerated: Bool
    var isNullable: Bool

    enum CodingKeys: String, CodingKey {
      case tableId, ordinalPosition, name, format, typeSchema, defaultValue, identityGeneration
      case isGenerated, isNullable
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      tableId = try container.decode(Int.self, forKey: .tableId)
      ordinalPosition = try container.decode(Int.self, forKey: .ordinalPosition)
      name = try container.decode(String.self, forKey: .name)
      format = try container.decode(String.self, forKey: .format)
      typeSchema = try container.decode(String.self, forKey: .typeSchema)
      hasDefault = try !container.decodeNil(forKey: .defaultValue)
      identityGeneration = try container.decode(
        IdentityGeneration?.self, forKey: .identityGeneration)
      isGenerated = try container.decode(Bool.self, forKey: .isGenerated)
      isNullable = try container.decode(Bool.self, forKey: .isNullable)
    }
  }

  struct PrimaryKey: Decodable {
    var tableId: Int
    var name: String
  }

  struct Function: Decodable {
    var schema: String
    var name: String
    var args: [Argument]
    /// The input argument types, e.g. `public.books`: what tells overloads apart.
    var identityArgumentTypes: String
    var returnTypeId: Int
    var returnTypeRelationId: Int?
    var isSetReturningFunction: Bool
    var prorows: Int?

    struct Argument: Decodable {
      var mode: String
      var typeId: Int
    }
  }

  struct PostgresType: Decodable {
    var id: Int
    var schema: String
    var name: String
    var enums: [String]
    var typeRelationId: Int?
  }
}

enum IdentityGeneration: String, Decodable, Equatable {
  case always = "ALWAYS"
  case byDefault = "BY DEFAULT"
}
