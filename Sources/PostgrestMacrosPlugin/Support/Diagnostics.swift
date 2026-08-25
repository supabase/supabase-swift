//
//  Diagnostics.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// An error attached to a specific syntax node.
///
/// Throwing `MacroExpansionErrorMessage` puts the caret on the attribute, which is wrong for a
/// per-property misuse: the reader needs to see the property that caused it.
struct PostgrestDiagnostic: DiagnosticMessage {
  let message: String
  var severity: DiagnosticSeverity { .error }
  var diagnosticID: MessageID { MessageID(domain: "PostgrestMacros", id: message) }
}

extension MacroExpansionContext {
  /// Emits an error pointing at `node`.
  func error(_ message: String, at node: some SyntaxProtocol) {
    diagnose(Diagnostic(node: node, message: PostgrestDiagnostic(message: message)))
  }
}

extension DeclGroupSyntax {
  /// The first `@Relationship` attribute on a stored property, if any.
  ///
  /// Embeds belong to a selection, never to a relation (spec §4.5), so `@Table` rejects one.
  ///
  /// Forward-looking: `@Relationship` itself lands in stage 3, so today a user who writes it gets
  /// "unknown attribute" from the compiler first. Matching on the attribute *name* puts the guard
  /// in place for the day the macro exists.
  func postgrestRelationshipAttribute() -> AttributeSyntax? {
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      for attribute in variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
      where attribute.attributeName.trimmedDescription == "Relationship" {
        return attribute
      }
    }
    return nil
  }
}

extension DeclGroupSyntax {
  /// Reports every stored property whose type comes only from its initializer.
  ///
  /// `postgrestStoredProperties()` reads syntax, so `var isDone = false` gives it no annotation to
  /// read and the property is dropped from `CodingKeys`, `columnName(for:)`, `Insert` and `Update`.
  /// Nothing about that is loud: the initializer doubles as a decoding default, so the type still
  /// compiles, the column simply never round-trips, and the mistake surfaces only when a query
  /// names the key path and hits the generated `fatalError`. A macro cannot recover the type from
  /// the initializer expression, so the author is asked for an annotation instead.
  ///
  /// Reads `bindings.first` because ``postgrestDiagnoseMultipleBindings(macro:in:)`` has already
  /// rejected anything that binds more than one property.
  ///
  /// Returns `true` if anything was reported, so the caller can stop before emitting an expansion
  /// that leaves the column out.
  func postgrestDiagnoseUnannotatedProperties(
    macro: String,
    in context: some MacroExpansionContext
  ) -> Bool {
    var reported = false
    // The same members `postgrestStoredProperties()` would have taken, minus the annotation: a
    // static member or a computed property maps to no column by design, not by mistake.
    for member in memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" }),
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
        binding.typeAnnotation == nil,
        binding.postgrestIsStored
      else { continue }

      let name = identifier.identifier.text
      context.error(
        """
        \(macro) requires an explicit type annotation on '\(name)', as in \
        'var \(name): <Type> = ...' — without one the macro cannot infer the type, and the column \
        is dropped
        """,
        at: binding.pattern
      )
      reported = true
    }
    return reported
  }
}

extension DeclGroupSyntax {
  /// Reports every declaration that binds more than one property.
  ///
  /// `var task: String, note: String` declares two stored properties, and
  /// `postgrestStoredProperties()` reads only `bindings.first`, so `note` was dropped from every
  /// generated member.
  ///
  /// Iterating the bindings instead is not the fix. A marker attribute sits on the *declaration*,
  /// not on a binding, so `@Column("a") var x: Int, y: Int` would name one column twice and
  /// `@PrimaryKey var x: Int, y: Int` would claim two primary keys. And `var task, note: String`
  /// parses as one binding with no annotation and one with it, so the type would have to be
  /// propagated backwards the way the compiler does it. One property per declaration removes both
  /// problems, and the shape it asks for is the one this SDK writes anyway.
  ///
  /// Runs before ``postgrestDiagnoseUnannotatedProperties(macro:in:)``, so the shared-annotation
  /// form is told to split rather than to annotate a type it already has.
  func postgrestDiagnoseMultipleBindings(
    macro: String,
    in context: some MacroExpansionContext
  ) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" }),
        variable.bindings.count > 1
      else { continue }

      let names = variable.bindings.compactMap {
        $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
      }
      context.error(
        """
        \(macro) requires one stored property per declaration; split \
        \(postgrestNameList(names)) into separate declarations
        """,
        at: variable.bindings
      )
      reported = true
    }
    return reported
  }
}

/// `'a'`, then `'a' and 'b'`, then `'a', 'b' and 'c'`.
private func postgrestNameList(_ names: [String]) -> String {
  let quoted = names.map { "'\($0)'" }
  guard let last = quoted.last else { return "" }
  guard quoted.count > 1 else { return last }
  return quoted.dropLast().joined(separator: ", ") + " and " + last
}
