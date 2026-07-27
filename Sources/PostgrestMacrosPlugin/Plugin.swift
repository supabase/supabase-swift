import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct PostgrestMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    PrimaryKeyMacro.self,
    DefaultMacro.self,
    ColumnMacro.self,
    RelationshipMacro.self,
    TableMacro.self,
    SelectionOfMacro.self,
  ]
}
