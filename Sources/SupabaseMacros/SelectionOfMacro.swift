import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Types that map directly to PostgREST columns (not nested SelectionRepresentable).
private let knownPrimitives: Set<String> = [
  "UUID", "String", "Int", "Int32", "Int64", "Bool",
  "Double", "Float", "Decimal", "Date", "Data", "URL", "AnyJSON",
]

public struct SelectionOfMacro: MemberMacro, ExtensionMacro {

  // MARK: - ExtensionMacro — adds SelectionRepresentable with computed selectString

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: SelectionOfDiagnostic.notAStruct
        ))
      return []
    }

    let typeName = type.trimmedDescription
    let selectLines = buildSelectLines(from: structDecl)
    let body = selectLines.joined(separator: "\n")

    let ext: DeclSyntax = """
      extension \(raw: typeName): SelectionRepresentable {
        public static var selectString: String {
          var parts: [String] = []
      \(raw: body)
          return parts.joined(separator: ",")
        }
      }
      """
    return [ext.cast(ExtensionDeclSyntax.self)]
  }

  // MARK: - MemberMacro — adds CodingKeys

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
    let props = parseLetProperties(from: structDecl)
    let keyLines =
      props
      .map {
        $0.name == $0.columnName
          ? "  case \($0.name)"
          : "  case \($0.name) = \"\($0.columnName)\""
      }
      .joined(separator: "\n")

    return [
      """
      public enum CodingKeys: String, CodingKey {
      \(raw: keyLines)
      }
      """
    ]
  }
}

// MARK: - Property parsing for @SelectionOf (handles let bindings)

private struct LetPropertyInfo {
  let name: String
  let columnName: String
  let typeText: String
}

private func parseLetProperties(from decl: StructDeclSyntax) -> [LetPropertyInfo] {
  var result: [LetPropertyInfo] = []
  for member in decl.memberBlock.members {
    guard
      let varDecl = member.decl.as(VariableDeclSyntax.self),
      let binding = varDecl.bindings.first,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation,
      binding.accessorBlock == nil
    else { continue }

    let name = pattern.identifier.text
    let attrs = varDecl.attributes

    let columnName: String
    if let colAttr = attrs.attribute(named: "Column"),
      let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      columnName = seg.content.text
    } else {
      columnName = camelToSnake(name)
    }

    result.append(
      LetPropertyInfo(
        name: name,
        columnName: columnName,
        typeText: typeAnnotation.type.trimmedDescription
      ))
  }
  return result
}

// MARK: - Select string builder

private func buildSelectLines(from decl: StructDeclSyntax) -> [String] {
  var lines: [String] = []
  for member in decl.memberBlock.members {
    guard
      let varDecl = member.decl.as(VariableDeclSyntax.self),
      let binding = varDecl.bindings.first,
      let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation,
      binding.accessorBlock == nil
    else { continue }

    let name = pattern.identifier.text
    let attrs = varDecl.attributes

    // Resolve column name
    let columnName: String
    if let colAttr = attrs.attribute(named: "Column"),
      let args = colAttr.arguments?.as(LabeledExprListSyntax.self),
      let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      columnName = seg.content.text
    } else {
      columnName = camelToSnake(name)
    }

    // Unwrap Optional<T> to get the base type name
    let typeText =
      typeAnnotation.type.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))

    if knownPrimitives.contains(typeText) {
      // Plain column
      lines.append("    parts.append(\"\(columnName)\")")
    } else {
      // Nested SelectionRepresentable — resolved at runtime
      lines.append("    parts.append(\"\(columnName)(\\(\(typeText).selectString))\")")
    }
  }
  return lines
}

// MARK: - Diagnostics

enum SelectionOfDiagnostic: DiagnosticMessage {
  case notAStruct

  var message: String {
    switch self {
    case .notAStruct: return "@SelectionOf can only be applied to structs"
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}
