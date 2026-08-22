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
