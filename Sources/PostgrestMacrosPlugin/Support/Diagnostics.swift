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
  /// Embeds belong to a selection, never to a relation, so `@Table` rejects one.
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
  /// Reports every stored property whose type is left to its initializer.
  ///
  /// `postgrestStoredProperties()` reads syntax, so `var isDone = false` gives it no annotation to
  /// read and the property is dropped from `CodingKeys`, `Columns` and `Draft`.
  /// Nothing about that is loud: the initializer doubles as a decoding default, so the type still
  /// compiles, the column simply never round-trips, and the mistake surfaces only much later, at
  /// some unrelated call site that expected the column to exist. A macro cannot recover the type
  /// from the initializer expression, so the author is asked for an annotation instead.
  ///
  /// The condition is `postgrestType(at:)` returning `nil` — the very test the reader uses to skip
  /// a binding — so the two cannot drift apart. In particular `var draft, review: String` is not
  /// reported: `draft` has no annotation of its own but takes `review`'s, exactly as the reader
  /// resolves it.
  ///
  /// Returns `true` if anything was reported, so the caller can stop before emitting an expansion
  /// that leaves the column out.
  func postgrestDiagnoseUnannotatedProperties(
    macro: String,
    in context: some MacroExpansionContext
  ) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { $0.name.text == "static" })
      else { continue }

      let bindings = Array(variable.bindings)
      for index in bindings.indices {
        let binding = bindings[index]
        guard
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          binding.isPostgrestStored,
          bindings.postgrestType(at: index) == nil
        else { continue }

        let name = identifier.identifier.text
        context.error(
          """
          \(macro) requires an explicit type annotation on '\(name)', as in \
          'var \(name): <Type> = ...' — without one the macro cannot infer the type, and the \
          column is dropped
          """,
          at: binding.pattern
        )
        reported = true
      }
    }
    return reported
  }
}
