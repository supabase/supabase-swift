import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Types that map directly to PostgREST columns (not nested relationships).
private let knownPrimitives: Set<String> = [
  "UUID", "String", "Int", "Int8", "Int16", "Int32", "Int64",
  "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
  "Bool", "Double", "Float", "Decimal", "Date", "Data", "URL", "AnyJSON",
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
      context.diagnose(Diagnostic(node: node, message: SelectionOfDiagnostic.notAStruct))
      return []
    }

    let parentTableName = parseParentTableName(from: node) ?? ""
    let typeName = type.trimmedDescription
    let (selectLines, hasErrors) = buildSelectLines(
      from: structDecl,
      parentTableName: parentTableName,
      context: context
    )

    if hasErrors { return [] }

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

// MARK: - Property parsing for @SelectionOf (handles let and var bindings)

private struct LetPropertyInfo {
  let name: String
  let columnName: String  // JSON key for CodingKeys
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
    let isRelationship = attrs.containsAttribute(named: "Relationship")

    // Relationship fields use the field name as the JSON key (PostgREST alias),
    // not the snake_case column name. @Column override is irrelevant for relationships.
    let columnName: String
    if isRelationship {
      columnName = name
    } else if let colAttr = attrs.attribute(named: "Column"),
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

private func buildSelectLines(
  from decl: StructDeclSyntax,
  parentTableName: String,
  context: some MacroExpansionContext
) -> (lines: [String], hasErrors: Bool) {
  var lines: [String] = []
  var hasErrors = false

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

    // Resolve column name for primitive fields (@Column override or camelToSnake)
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

    // Determine the base Swift type (strip Optional and Array wrappers)
    let baseType = unwrapBaseType(typeAnnotation.type.trimmedDescription)

    if knownPrimitives.contains(baseType) {
      // Plain scalar column
      lines.append("    parts.append(\"\(columnName)\")")
    } else if let relAttr = attrs.attribute(named: "Relationship") {
      // @Relationship — generate PostgREST disambiguation: alias:table!fk(subselect)
      let (rootType, fkProperty) = parseRelationshipKeyPath(
        from: relAttr, parentTableName: parentTableName)
      // Produces: parts.append("name:\(BaseType.tableName)!\(RootType.columnName(for: \.fkProp))(\(BaseType.selectString))")
      lines.append(
        "    parts.append(\"\(name):\\(\(baseType).tableName)!\\(\(rootType).columnName(for: \\.\(fkProperty)))(\\(\(baseType).selectString))\")"
      )
    } else {
      // Non-primitive without @Relationship — emit diagnostic
      context.diagnose(
        Diagnostic(
          node: Syntax(varDecl),
          message: SelectionOfDiagnostic.nonPrimitiveRequiresRelationship(typeName: baseType)
        ))
      hasErrors = true
    }
  }
  return (lines, hasErrors)
}

// MARK: - Helpers

/// Parses the table type name from @SelectionOf(Message.self) → "Message".
private func parseParentTableName(from node: AttributeSyntax) -> String? {
  guard
    let args = node.arguments?.as(LabeledExprListSyntax.self),
    let first = args.first,
    let memberAccess = first.expression.as(MemberAccessExprSyntax.self),
    let base = memberAccess.base?.as(DeclReferenceExprSyntax.self)
  else { return nil }
  return base.baseName.text
}

/// Strips Optional (`?`) and Array (`[T]`) wrappers to get the base type name.
private func unwrapBaseType(_ typeText: String) -> String {
  var t = typeText
  if t.hasSuffix("?") { t = String(t.dropLast()) }
  if t.hasPrefix("[") && t.hasSuffix("]") {
    t = String(t.dropFirst().dropLast())
    if t.hasSuffix("?") { t = String(t.dropLast()) }
  }
  return t
}

/// Extracts (rootTypeName, fkPropertyName) from a @Relationship attribute.
/// For \Message.senderId → ("Message", "senderId").
/// For \.senderId → (parentTableName, "senderId").
private func parseRelationshipKeyPath(
  from attr: AttributeSyntax,
  parentTableName: String
) -> (rootType: String, fkProperty: String) {
  guard
    let args = attr.arguments?.as(LabeledExprListSyntax.self),
    let first = args.first,
    let keyPathExpr = first.expression.as(KeyPathExprSyntax.self)
  else { return (parentTableName, "") }

  let rootType: String
  if let root = keyPathExpr.root {
    rootType = root.trimmedDescription
  } else {
    rootType = parentTableName
  }

  let fkProperty =
    keyPathExpr.components
    .compactMap { $0.component.as(KeyPathPropertyComponentSyntax.self) }
    .first?.declName.baseName.text ?? ""

  return (rootType, fkProperty)
}

// MARK: - Diagnostics

enum SelectionOfDiagnostic: DiagnosticMessage {
  case notAStruct
  case nonPrimitiveRequiresRelationship(typeName: String)

  var message: String {
    switch self {
    case .notAStruct:
      return "@SelectionOf can only be applied to structs"
    case .nonPrimitiveRequiresRelationship(let typeName):
      return "Embedded type '\(typeName)' in '@SelectionOf' requires '@Relationship'"
    }
  }
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}
