//
//  StoredProperty.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax

/// One stored property of an annotated type, with the marker attributes that affect it.
struct StoredProperty {
  var name: String
  var type: String
  var isOptional: Bool
  var isPrimaryKey: Bool
  var hasDefault: Bool
  var explicitColumn: String?

  /// The database column name: an explicit `@Column`, otherwise the snake_case form.
  var columnName: String { explicitColumn ?? camelToSnakeCase(name) }

  /// The property's type made optional, or left alone if it already is.
  var optionalType: String { isOptional ? type : "\(type)?" }
}

extension DeclGroupSyntax {
  /// Reads the stored properties, skipping computed properties and static members.
  ///
  /// A key path to a skipped property therefore maps to no column, which is what the generated
  /// `columnName(for:)` traps on.
  ///
  /// A property whose type comes only from its initializer is skipped as well — there is no
  /// annotation to read. That one is a mistake rather than a design, so
  /// `postgrestDiagnoseUnannotatedProperties(macro:in:)` reports it and the macro stops before
  /// anything reaches here.
  func postgrestStoredProperties() -> [StoredProperty] {
    memberBlock.members.compactMap { member -> StoredProperty? in
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" }),
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
        let annotation = binding.typeAnnotation?.type,
        binding.accessorBlock == nil
      else { return nil }

      let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
      func attribute(_ name: String) -> AttributeSyntax? {
        attributes.first { $0.attributeName.trimmedDescription == name }
      }

      let column =
        attribute("Column")?
        .arguments?.as(LabeledExprListSyntax.self)?.first?
        .expression.as(StringLiteralExprSyntax.self)?
        .representedLiteralValue

      let typeText = annotation.trimmedDescription
      return StoredProperty(
        name: identifier.identifier.text,
        type: typeText,
        isOptional: typeText.hasSuffix("?") || typeText.hasPrefix("Optional<"),
        isPrimaryKey: attribute("PrimaryKey") != nil,
        hasDefault: attribute("Default") != nil,
        explicitColumn: column
      )
    }
  }

  /// The access level to repeat on generated members, with a trailing space, or `""`.
  ///
  /// Only `public` and `package` are propagated. A protocol witness must be at least as accessible
  /// as the conformance, and an internal witness already satisfies a `fileprivate` or `private`
  /// one.
  var postgrestAccessLevel: String {
    for modifier in modifiers {
      switch modifier.name.tokenKind {
      case .keyword(.public): return "public "
      case .keyword(.package): return "package "
      default: continue
      }
    }
    return ""
  }
}
