import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SupabaseMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    PrimaryKeyMacro.self,
    DefaultMacro.self,
    ColumnMacro.self,
    RelationshipMacro.self,
    TableMacro.self,
    // SelectionOfMacro added in Task 5
  ]
}
