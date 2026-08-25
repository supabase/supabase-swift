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

extension PatternBindingSyntax {
  /// Whether the binding stores a value, rather than computing one.
  ///
  /// A non-nil `accessorBlock` is not enough to call a property computed: `willSet` and `didSet`
  /// land in that same block, and an observed property still holds a value and still needs its
  /// column. Anything else in the block computes the value instead — an explicit `get`, a `_read`
  /// or `unsafeAddress` accessor, or a bare code block standing in for an implicit getter — and
  /// maps to no column.
  var postgrestIsStored: Bool {
    guard let accessorBlock else { return true }
    switch accessorBlock.accessors {
    case .getter:
      // `var summary: String { htmlURL }` — an implicit getter, with no accessor to inspect.
      return false
    case .accessors(let accessors):
      return accessors.allSatisfy {
        switch $0.accessorSpecifier.tokenKind {
        case .keyword(.willSet), .keyword(.didSet): return true
        default: return false
        }
      }
    }
  }
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
  ///
  /// Reading `bindings.first` is safe for the same reason: a declaration that binds more than one
  /// property is rejected by `postgrestDiagnoseMultipleBindings(macro:in:)` first, so whatever
  /// gets here binds exactly one.
  func postgrestStoredProperties() -> [StoredProperty] {
    memberBlock.members.compactMap { member -> StoredProperty? in
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" }),
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
        let annotation = binding.typeAnnotation?.type,
        binding.postgrestIsStored
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
