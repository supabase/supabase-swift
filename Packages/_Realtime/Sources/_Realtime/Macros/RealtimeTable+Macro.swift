//
//  RealtimeTable+Macro.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import _RealtimeTableMacros

/// Synthesizes `RealtimeTable` conformance for a struct, enabling typed `Filter<T>` in postgres change streams.
///
/// ```swift
/// @RealtimeTable(schema: "public", table: "messages")
/// struct Message: Codable, Sendable {
///   var id: UUID
///   var roomId: UUID
///   var text: String
/// }
///
/// // Enables typed filters:
/// channel.changes(to: Message.self, where: .eq(\.roomId, roomId))
/// ```
///
/// Column names follow `CodingKeys` if defined; otherwise camelCase is converted to snake_case.
@attached(extension, conformances: RealtimeTable, names: named(schema), named(tableName), named(columnName))
public macro RealtimeTable(schema: String, table: String) =
  #externalMacro(module: "_RealtimeTableMacroPlugin", type: "RealtimeTableMacro")
