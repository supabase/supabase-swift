//
//  Naming.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

import SwiftParser

/// Turns Postgres names into Swift identifiers.
enum Naming {
  /// Property names `@Table`'s expansion cannot take, and which it does not diagnose itself: the
  /// members it adds to the type, and `self`, which as a `Draft.init` parameter would shadow the
  /// `self` the initializer assigns through.
  static let tableMembers: Set = [
    "columns", "selectString", "relationName", "primaryKeyColumns",
    "Draft", "Columns", "CodingKeys", "Schema", "self",
  ]

  /// Names a computed member cannot take in `Columns`, which is a struct of one `let` per column
  /// plus `init()`.
  static let columnsMembers: Set = ["init", "self"]

  /// Case names an enum does not take. They compile, but `Status.init` and `Status.self` name the
  /// initializer and the type itself, and `rawValue` reads as the property every case has.
  static let enumMembers: Set = ["rawValue", "init", "self"]

  /// The type names the generated file or `@Table`'s expansion refer to unqualified. A generated
  /// type with one of these names would shadow it — including the types `@Table` nests inside the
  /// struct: in `struct Draft`, the expansion's `PostgrestColumn<Draft, …>` inside `Columns` finds
  /// the nested `Draft.Draft` first.
  static let referencedTypes: Set = [
    "Bool", "Date", "Decimal", "Double", "Int", "JSONValue", "String", "UUID",
    "Decodable", "Encodable", "Sendable", "CodingKey", "Optional", "Array",
    "Codable", "Hashable", "PostgrestFilterValue",
    "PostgREST", "PostgrestMacros", "PostgrestSchema", "PublicSchema", "Foundation", "Swift",
    "Type", "Self", "Any", "Protocol",
    "Draft", "Columns", "CodingKeys", "Schema",
    "PostgrestColumn", "PostgrestNullableColumn", "PostgrestGeneratedColumn", "PostgrestNotNull",
    "PostgrestNullable", "PostgrestRelation", "PostgrestKeyedRelation", "PostgrestWritableRelation",
    "PostgrestEmbed", "PostgrestComputedField", "PostgrestToOneRelation", "PostgrestToManyRelation",
  ]

  /// `snake_case` (or any other spelling) to `lowerCamelCase`, escaped. `1st_place` becomes
  /// `_1stPlace`, `class` becomes `` `class` ``.
  static func propertyName(_ name: String) -> String {
    var words = words(of: name)
    if let first = words.first {
      words[0] = first.allSatisfy(\.isUppercase) ? first.lowercased() : lowercasedFirst(first)
    }
    return identifier(words.enumerated().map { $0 == 0 ? $1 : uppercasedFirst($1) }.joined())
  }

  /// `snake_case` (or any other spelling) to `UpperCamelCase`, escaped.
  static func typeName(_ name: String) -> String {
    identifier(words(of: name).map(uppercasedFirst).joined())
  }

  /// `name` as it must be spelled in source: as is when it is a valid identifier, in backticks when
  /// it is a keyword. A name that is neither, such as one that starts with a digit, is prefixed
  /// with `_`; one with no usable character at all becomes `unnamed`.
  static func identifier(_ name: String) -> String {
    // A leading digit gets `_` rather than backticks: since Swift 6.2 backticks also accept raw
    // identifiers such as `` `1st` ``, which read worse than `_1st`.
    let base = name.first?.isNumber == true ? "_" + name : name
    return [base, "`\(base)`"].first {
      !name.isEmpty && $0.isValidSwiftIdentifier(for: .variableName)
    } ?? "unnamed"
  }

  /// The words of a Postgres name: runs of letters and digits. Everything else separates them, so
  /// `user_id`, `user-id` and `user id` all give `user`, `id`.
  private static func words(of name: String) -> [String] {
    name.split { !($0.isLetter || $0.isNumber) }.map(String.init)
  }

  /// `name` without the backticks ``identifier(_:)`` may have added.
  static func unescaped(_ name: String) -> String {
    name.filter { $0 != "`" }
  }

  private static func uppercasedFirst(_ word: String) -> String {
    word.prefix(1).uppercased() + word.dropFirst()
  }

  private static func lowercasedFirst(_ word: String) -> String {
    word.prefix(1).lowercased() + word.dropFirst()
  }
}
