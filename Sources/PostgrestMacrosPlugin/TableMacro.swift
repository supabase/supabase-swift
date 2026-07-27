import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TableMacro: MemberMacro {

  // MARK: - MemberMacro — all protocol implementations + CodingKeys

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: TableMacroDiagnostic.notAStruct
        ))
      return []
    }

    var hasRelationshipFields = false
    for member in structDecl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
      if let relAttr = varDecl.attributes.attribute(named: "Relationship") {
        context.diagnose(
          Diagnostic(node: relAttr, message: TableMacroDiagnostic.relationshipNotAllowed))
        hasRelationshipFields = true
      }
    }
    if hasRelationshipFields { return [] }

    var hasLetBindings = false
    for member in structDecl.memberBlock.members {
      guard
        let varDecl = member.decl.as(VariableDeclSyntax.self),
        varDecl.bindingSpecifier.tokenKind == .keyword(.let),
        let binding = varDecl.bindings.first,
        binding.accessorBlock == nil
      else { continue }
      context.diagnose(
        Diagnostic(node: Syntax(varDecl), message: TableMacroDiagnostic.letBindingNotAllowed))
      hasLetBindings = true
    }
    if hasLetBindings { return [] }

    let args = try TableArgs(from: node)
    let typeName = structDecl.name.text
    let props = parseStoredProperties(from: structDecl)

    var members: [DeclSyntax] = []

    // 1. tableName
    members.append("public static let tableName: String = \"\(raw: args.tableName)\"")

    // 2. schema
    members.append("public static let schema: String = \"\(raw: args.schema)\"")

    // 3. selectString
    members.append("public static let selectString: String = \"*\"")

    // 4. columnName
    members.append(makeColumnName(typeName: typeName, props: props))

    // 5. Insert + Update (non-readOnly only)
    if !args.readOnly {
      members.append(makeInsertStruct(from: props))
      members.append(makeUpdateStruct(from: props))
    }

    // 6. CodingKeys
    members.append(makeCodingKeys(from: props))

    return members
  }
}

// MARK: - Member declaration builders

private func makeColumnName(typeName: String, props: [StoredPropertyInfo]) -> DeclSyntax {
  // "\n  " puts each subsequent case at 2 absolute spaces, matching the first case's
  // effective position after the template strips 4 spaces of leading indent.
  let cases = props.map {
    "if erased == \\\(typeName).\($0.name) { return \"\($0.columnName)\" }"
  }.joined(separator: "\n  ")
  return """
    public static func columnName<V>(for keyPath: KeyPath<\(raw: typeName), V>) -> String {
      let erased = keyPath as AnyKeyPath
      \(raw: cases)
      preconditionFailure("Unknown column keypath on \(raw: typeName) — macro bug")
    }
    """
}

private func makeInsertStruct(from props: [StoredPropertyInfo]) -> DeclSyntax {
  let insertProps = props.filter { !$0.isPrimaryKey }
  let vars = insertProps.map { prop -> String in
    let base = prop.typeSyntax.trimmedDescription.trimmingCharacters(
      in: CharacterSet(charactersIn: "?"))
    if prop.hasDefault || prop.isOptional {
      return "  public var \(prop.name): \(base)? = nil"
    } else {
      return "  public var \(prop.name): \(base)"
    }
  }.joined(separator: "\n")
  let keys = insertProps.map {
    "  " + codingKeyLine(swiftName: $0.name, columnName: $0.columnName)
  }.joined(separator: "\n")

  return """
    public struct Insert: Encodable {
    \(raw: vars)
      public enum CodingKeys: String, CodingKey {
    \(raw: keys)
      }
    }
    """
}

private func makeUpdateStruct(from props: [StoredPropertyInfo]) -> DeclSyntax {
  let updateProps = props.filter { !$0.isPrimaryKey }
  let vars = updateProps.map { prop -> String in
    let base = prop.typeSyntax.trimmedDescription.trimmingCharacters(
      in: CharacterSet(charactersIn: "?"))
    return "  public var \(prop.name): \(base)? = nil"
  }.joined(separator: "\n")
  let keys = updateProps.map {
    "  " + codingKeyLine(swiftName: $0.name, columnName: $0.columnName)
  }.joined(separator: "\n")

  return """
    public struct Update: Encodable {
    \(raw: vars)
      public enum CodingKeys: String, CodingKey {
    \(raw: keys)
      }
    }
    """
}

private func makeCodingKeys(from props: [StoredPropertyInfo]) -> DeclSyntax {
  let lines = props.map { codingKeyLine(swiftName: $0.name, columnName: $0.columnName) }
  let keys = lines.joined(separator: "\n")
  return """
    public enum CodingKeys: String, CodingKey {
    \(raw: keys)
    }
    """
}

private func codingKeyLine(swiftName: String, columnName: String) -> String {
  swiftName == columnName
    ? "    case \(swiftName)"
    : "    case \(swiftName) = \"\(columnName)\""
}

// MARK: - Argument parsing

struct TableArgs {
  let tableName: String
  let schema: String
  let readOnly: Bool

  init(from node: AttributeSyntax) throws {
    guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
      throw MacroExpansionError("@Table requires a table name argument")
    }

    guard let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    else {
      throw MacroExpansionError("@Table first argument must be a string literal")
    }
    tableName = seg.content.text

    if let schemaArg = args.first(where: { $0.label?.text == "schema" }),
      let strLit = schemaArg.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      schema = seg.content.text
    } else {
      schema = "public"
    }

    if let roArg = args.first(where: { $0.label?.text == "readOnly" }),
      let boolLit = roArg.expression.as(BooleanLiteralExprSyntax.self)
    {
      readOnly = boolLit.literal.tokenKind == .keyword(.true)
    } else {
      readOnly = false
    }
  }
}

// MARK: - Diagnostics

enum TableMacroDiagnostic: DiagnosticMessage {
  case notAStruct
  case relationshipNotAllowed
  case letBindingNotAllowed

  var message: String {
    switch self {
    case .notAStruct:
      return "@Table can only be applied to structs"
    case .relationshipNotAllowed:
      return
        "'@Relationship' fields are not allowed in '@Table'. Declare a '@SelectionOf' struct to join related tables."
    case .letBindingNotAllowed:
      return "@Table requires stored properties to use 'var', not 'let'"
    }
  }
  var diagnosticID: MessageID { .init(domain: "PostgrestMacrosPlugin", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}

struct MacroExpansionError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { description = message }
}
