//
//  DatabaseModelTests.swift
//  SupabaseTypegenTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Testing

@testable import SupabaseTypegen

@Suite
struct DatabaseModelTests {
  private func model(_ data: Data, schemas: [String] = []) throws -> DatabaseModel {
    try DatabaseModel(decodeGeneratorMetadata(data), schemas: schemas)
  }

  private func relation(_ model: DatabaseModel, _ schema: String, _ name: String) throws
    -> DatabaseModel.Relation
  {
    try #require(model.relations.first { $0.name == QualifiedName(schema: schema, name: name) })
  }

  @Test
  func relationsAreSortedBySchemaThenName() throws {
    let names = try model(Fixture.postgrestTypegen).relations.map(\.name)
    #expect(names == names.sorted())
    #expect(names.first == QualifiedName(schema: "inventory", name: "items"))
    #expect(names.count == 16 + 5 + 1 + 1)
  }

  @Test
  func everyCollectionIsARelationOfItsKind() throws {
    let model = try model(Fixture.postgrestTypegen)
    #expect(try relation(model, "public", "todos").kind == .table)
    #expect(
      try relation(model, "public", "todos_view").kind
        == .view(isInsertEnabled: true, isUpdateEnabled: true))
    #expect(
      try relation(model, "public", "user_todos_summary_view").kind
        == .view(isInsertEnabled: false, isUpdateEnabled: false))
    #expect(try relation(model, "public", "todos_matview").kind == .materializedView)
    #expect(try relation(model, "public", "foreign_table").kind == .foreignTable)
  }

  @Test
  func viewFlagsFallBackToIsUpdatable() throws {
    func kind(isUpdatable: Bool, isInsertEnabled: Bool?) throws -> DatabaseModel.Relation.Kind {
      let data = Fixture.integration { object in
        var view = (object["views"] as! [[String: Any]])
          .first { $0["name"] as? String == "updatable_view" }!
        view["is_updatable"] = isUpdatable
        view["is_insert_enabled"] = isInsertEnabled
        view["is_update_enabled"] = nil
        object["views"] = [view]
      }
      return try relation(model(data), "public", "updatable_view").kind
    }
    #expect(
      try kind(isUpdatable: false, isInsertEnabled: nil)
        == .view(isInsertEnabled: false, isUpdateEnabled: false))
    #expect(
      try kind(isUpdatable: true, isInsertEnabled: false)
        == .view(isInsertEnabled: false, isUpdateEnabled: true))
  }

  @Test
  func columnsAreInOrdinalOrderWithTheirMetadata() throws {
    let counters = try relation(model(Fixture.integration), "public", "counters")
    #expect(
      counters.columns == [
        .init(
          name: "id", format: "int4", typeSchema: "pg_catalog", enumID: nil, hasDefault: false,
          identityGeneration: .always, isGenerated: false, isNullable: false),
        .init(
          name: "count", format: "int4", typeSchema: "pg_catalog", enumID: nil, hasDefault: false,
          identityGeneration: nil, isGenerated: false, isNullable: false),
        .init(
          name: "doubled", format: "int4", typeSchema: "pg_catalog", enumID: nil, hasDefault: true,
          identityGeneration: nil, isGenerated: true, isNullable: true),
      ])
  }

  @Test
  func primaryKeyIsInColumnOrder() throws {
    let model = try model(Fixture.postgrestTypegen)
    #expect(try relation(model, "public", "events").primaryKey == ["id", "created_at"])
    #expect(
      try relation(model, "public", "table_with_primary_key_other_than_id").primaryKey
        == ["other_id"])
    #expect(try relation(model, "public", "empty").primaryKey == [])
    #expect(try relation(model, "public", "todos_view").primaryKey == [])
  }

  @Test
  func enumsAreKeyedByTypeIDAndResolvedPerSchema() throws {
    let model = try model(Fixture.postgrestTypegen)
    let enumNames = Set(model.enums.values.map(\.name))
    #expect(
      enumNames == [
        QualifiedName(schema: "inventory", name: "user_status"),
        QualifiedName(schema: "public", name: "meme_status"),
        QualifiedName(schema: "public", name: "user_status"),
      ])
    for (id, enumType) in model.enums {
      #expect(enumType.id == id)
    }

    func statusEnum(_ schema: String, _ table: String) throws -> DatabaseModel.EnumType {
      let columns = try relation(model, schema, table).columns
      let enumID = try #require(columns.first { $0.name == "status" }?.enumID)
      return try #require(model.enums[enumID])
    }
    #expect(
      try statusEnum("inventory", "users").name
        == QualifiedName(schema: "inventory", name: "user_status"))
    #expect(
      try statusEnum("public", "users").name
        == QualifiedName(schema: "public", name: "user_status"))
  }

  @Test
  func enumValuesAreInDeclarationOrder() throws {
    let model = try model(Fixture.integration)
    #expect(model.enums.values.map(\.values) == [["ONLINE", "OFFLINE"]])
  }

  @Test
  func functionsAttachToTheRelationOfTheirSingleArgument() throws {
    let model = try model(Fixture.integration)
    let channels = try relation(model, "public", "channels")
    let messages = QualifiedName(schema: "public", name: "messages")
    #expect(
      channels.functions.map(\.name.name) == ["channel_messages", "first_message", "shouted_slug"])

    let channelMessages = channels.functions[0]
    #expect(channelMessages.signature == "channels")
    #expect(channelMessages.returnsRow)
    #expect(channelMessages.returnRelation == messages)
    #expect(channelMessages.isSetReturning)
    #expect(channelMessages.rows == 1000)

    let firstMessage = channels.functions[1]
    #expect(firstMessage.returnRelation == messages)
    #expect(!firstMessage.isSetReturning)

    let shoutedSlug = channels.functions[2]
    #expect(shoutedSlug.returnType == QualifiedName(schema: "pg_catalog", name: "text"))
    #expect(!shoutedSlug.returnsRow)
    #expect(shoutedSlug.returnRelation == nil)

    let attached = model.relations.flatMap(\.functions).count
    #expect(attached == 3)
  }

  @Test
  func defaultSelectsEveryDocumentSchema() throws {
    #expect(try model(Fixture.postgrestTypegen).schemas == ["inventory", "public"])
  }

  @Test
  func schemaSelectionKeepsOnlyThoseRelations() throws {
    let model = try model(Fixture.postgrestTypegen, schemas: ["inventory"])
    #expect(model.schemas == ["inventory"])
    #expect(
      model.relations.map(\.name) == [
        QualifiedName(schema: "inventory", name: "items"),
        QualifiedName(schema: "inventory", name: "users"),
      ])
    #expect(model.enums.count == 3)
  }

  @Test(arguments: [Fixture.integration, Fixture.postgrestTypegen])
  func modelDoesNotDependOnDocumentOrder(document: Data) throws {
    var reversed = try decodeGeneratorMetadata(document)
    reversed.schemas.reverse()
    reversed.tables.reverse()
    reversed.views.reverse()
    reversed.materializedViews.reverse()
    reversed.foreignTables.reverse()
    reversed.columns.reverse()
    reversed.primaryKeys.reverse()
    reversed.functions.reverse()
    reversed.types.reverse()

    #expect(DatabaseModel(reversed) == (try model(document)))
  }
}
