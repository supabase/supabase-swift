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

/// The `@Relationship` foreign key rendered as a namespace reference, `Comment.columns.todoID`,
/// or `nil` if the argument is not a single-component key path with a written root.
///
/// The root is what makes the reference resolvable from the expansion, and it is why the key path
/// has to be written in full: `\.todoID` infers its root from context the macro cannot see.
///
/// One component, because a foreign key is one column. A longer path would name something inside a
/// column's value, which is not a relationship.
func postgrestForeignKeyReference(_ attribute: AttributeSyntax) -> String? {
  guard
    let keyPath = attribute.arguments?.as(LabeledExprListSyntax.self)?.first?
      .expression.as(KeyPathExprSyntax.self),
    let root = keyPath.root?.trimmedDescription,
    keyPath.components.count == 1,
    let property = keyPath.components.first?.component.as(KeyPathPropertyComponentSyntax.self)
  else { return nil }
  return "\(root).columns.\(property.declName.baseName.trimmedDescription)"
}

extension DeclGroupSyntax {
  /// The first `@Relationship` attribute on a stored property, if any.
  ///
  /// Embeds belong to a selection, never to a relation, so `@Table` rejects one. A relation carries
  /// columns; the property naming the other side of a join is declared by the selection that wants
  /// it embedded.
  ///
  /// Matching on the attribute *name* rather than resolving the macro is what keeps this working
  /// from `@Table`, which never expands `@Relationship` itself.
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

extension DeclGroupSyntax {
  /// Reports every `@Relationship` whose argument is not a usable foreign key key path.
  ///
  /// Left alone, the property falls through to the plain-column path and the reader gets
  /// "value of type 'Todo.Columns' has no member 'comments'" on a line they did not write — the
  /// column the embed deliberately does not have.
  ///
  /// Returns `true` if anything was reported.
  func postgrestDiagnoseRelationships(in context: some MacroExpansionContext) -> Bool {
    var reported = false
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      for attribute in variable.attributes.compactMap({ $0.as(AttributeSyntax.self) })
      where attribute.attributeName.trimmedDescription == "Relationship"
        && postgrestForeignKeyReference(attribute) == nil
      {
        context.error(
          """
          @Relationship requires a key path to one foreign key column, written with its root, \
          as in '@Relationship(\\Comment.todoID)'
          """,
          at: attribute
        )
        reported = true
      }
    }
    return reported
  }
}
