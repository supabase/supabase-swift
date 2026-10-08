//
//  MarkerMacros.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// The marker attributes carry no expansion of their own — the enclosing macro reads them off the
/// properties: `@Table` reads `@Column`, `@PrimaryKey` and `@Default`, and `@SelectionOf` reads
/// `@Column` and `@Relationship`.
///
/// The declarations still matter. `@Relationship(\Comment.todoID)` is type-checked as a written
/// expression, so a key path naming no such column is an error at the attribute, before anything
/// this plugin emits is compiled.
public struct MarkerMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
}
