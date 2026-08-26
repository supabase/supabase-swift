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

/// Whether a written type is spelled as an `Optional`.
///
/// Both spellings have to be recognized everywhere optionality is decided: `Int?` and
/// `Optional<Int>` are the same type, and a generated schema can emit either. Recognizing one and
/// not the other is what let an `Optional<T>` field lose the `= nil` default in a generated
/// initializer while a `?`-spelled one kept it.
///
/// A `Swift.Optional<Int>` spelling is not matched. It is legal but vanishingly rare, and a macro
/// cannot resolve module qualification from syntax alone.
func postgrestIsOptionalType(_ type: String) -> Bool {
  type.hasSuffix("?") || type.hasPrefix("Optional<")
}

extension DeclGroupSyntax {
  /// Reads the stored properties, skipping computed properties and static members.
  ///
  /// A key path to a skipped property therefore maps to no column, which is what the generated
  /// `columnName(for:)` traps on.
  ///
  /// Three shapes are easy to get wrong, so each is spelled out:
  ///
  /// - **Every binding counts.** `var task: String, note: String` is one `VariableDeclSyntax` with
  ///   two bindings. Reading only the first silently drops `note` from `CodingKeys`, the column
  ///   map and `Insert`.
  /// - **A shared annotation sits on the last binding.** In `var draft, review: String` only
  ///   `review` carries the type, so a binding without one takes the next annotation forward —
  ///   but only when it has no initializer of its own. In `var a = 1, b: String`, `a` is an `Int`
  ///   inferred from its initializer, and borrowing `b`'s annotation would type it `String`.
  /// - **Observers keep a property stored.** `var task: String = "" { didSet { … } }` has an
  ///   accessor block, so testing `accessorBlock == nil` excludes it as though it were computed.
  ///
  /// A property whose type is inferred from an initializer (`var isDone = false`) is still
  /// skipped: a macro sees syntax, not types, so there is no annotation to read. Guessing from the
  /// initializer is not the macro's to do, so `postgrestDiagnoseUnannotatedProperties(macro:in:)`
  /// reports it and the expansion stops before anything reaches here.
  func postgrestStoredProperties() -> [StoredProperty] {
    memberBlock.members.flatMap { member -> [StoredProperty] in
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" })
      else { return [] }

      // Marker attributes sit on the declaration, not the binding, so every binding in
      // `@Default var a, b: Bool` carries them.
      let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
      func attribute(_ name: String) -> AttributeSyntax? {
        attributes.first { $0.attributeName.trimmedDescription == name }
      }

      let column =
        attribute("Column")?
        .arguments?.as(LabeledExprListSyntax.self)?.first?
        .expression.as(StringLiteralExprSyntax.self)?
        .representedLiteralValue

      let bindings = Array(variable.bindings)
      return bindings.indices.compactMap { index -> StoredProperty? in
        let binding = bindings[index]
        guard
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          binding.isPostgrestStored,
          let annotation = bindings.postgrestType(at: index)
        else { return nil }

        let typeText = annotation.trimmedDescription
        return StoredProperty(
          name: identifier.identifier.text,
          type: typeText,
          isOptional: postgrestIsOptionalType(typeText),
          isPrimaryKey: attribute("PrimaryKey") != nil,
          hasDefault: attribute("Default") != nil,
          explicitColumn: column
        )
      }
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

extension PatternBindingSyntax {
  /// Whether this binding is stored rather than computed.
  ///
  /// No accessor block means stored. An accessor block holding only `willSet`/`didSet` is a
  /// stored property with observers, which still has storage and still round-trips to a column.
  /// Anything else — an explicit `get`, or the implicit getter of `var x: Int { 1 }` — is
  /// computed and has no column.
  var isPostgrestStored: Bool {
    guard let accessorBlock else { return true }

    switch accessorBlock.accessors {
    case .accessors(let accessors):
      return accessors.allSatisfy { accessor in
        switch accessor.accessorSpecifier.tokenKind {
        case .keyword(.willSet), .keyword(.didSet): true
        default: false
        }
      }
    case .getter:
      // `var x: Int { 1 }` — an implicit getter, so computed.
      return false
    }
  }
}

extension [PatternBindingSyntax] {
  /// The type of the binding at `index`, resolving a shared annotation.
  ///
  /// `var draft, review: String` puts the annotation on `review` alone, so an unannotated binding
  /// looks forward for one. A binding with its own initializer does not: in `var a = 1, b: String`
  /// the initializer is what types `a`, and it is not the macro's to read.
  func postgrestType(at index: Int) -> TypeSyntax? {
    if let annotation = self[index].typeAnnotation?.type { return annotation }
    guard self[index].initializer == nil else { return nil }
    return self[index...].lazy.compactMap { $0.typeAnnotation?.type }.first
  }
}
