import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SupabaseMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    PrimaryKeyMacro.self,
    DefaultMacro.self,
    ColumnMacro.self,
    RelationshipMacro.self,
    // TableMacro and SelectionOfMacro added in Tasks 4–5
  ]
}
