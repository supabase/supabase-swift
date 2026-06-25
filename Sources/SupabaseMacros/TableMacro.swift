import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TableMacro: MemberMacro, ExtensionMacro {

  // MARK: - ExtensionMacro — adds protocol conformance

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    // Suppress extension when @Relationship fields are present (diagnosed in MemberMacro)
    if let structDecl = declaration.as(StructDeclSyntax.self) {
      let hasRelationship = structDecl.memberBlock.members.contains { member in
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
        return varDecl.attributes.attribute(named: "Relationship") != nil
      }
      if hasRelationship { return [] }
    }

    let args = try TableArgs(from: node)
    let typeName = type.trimmedDescription
    let conformance = args.readOnly ? "ReadOnlyTableRepresentable" : "TableRepresentable"

    let ext: DeclSyntax = """
      extension \(raw: typeName): \(raw: conformance) {
        public static let tableName = "\(raw: args.tableName)"
        public static let schema = "\(raw: args.schema)"
        public static let selectString = "*"
      }
      """
    return [ext.cast(ExtensionDeclSyntax.self)]
  }

  // MARK: - MemberMacro — adds Insert, Update, CodingKeys, columnName

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
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

    // @Relationship is not allowed in @Table — emit diagnostic on each offending attribute
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

    // @Table requires var bindings — let properties trigger a diagnostic and halt expansion
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

    if !args.readOnly {
      members.append(makeInsert(from: props))
      members.append(makeUpdate(from: props))
    }
    members.append(makeCodingKeys(from: props))
    members.append(makeColumnName(typeName: typeName, from: props))

    return members
  }
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

    // First positional arg: table name
    guard let first = args.first,
      let strLit = first.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    else {
      throw MacroExpansionError("@Table first argument must be a string literal")
    }
    tableName = seg.content.text

    // schema: label
    if let schemaArg = args.first(where: { $0.label?.text == "schema" }),
      let strLit = schemaArg.expression.as(StringLiteralExprSyntax.self),
      let seg = strLit.segments.first?.as(StringSegmentSyntax.self)
    {
      schema = seg.content.text
    } else {
      schema = "public"
    }

    // readOnly: label
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
  var diagnosticID: MessageID { .init(domain: "SupabaseMacros", id: "\(self)") }
  var severity: DiagnosticSeverity { .error }
}

struct MacroExpansionError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { description = message }
}

// MARK: - Member synthesis helpers

private func makeInsert(from props: [StoredPropertyInfo]) -> DeclSyntax {
  // Exclude @PrimaryKey; @Default fields become Optional with = nil
  let insertProps = props.filter { !$0.isPrimaryKey }

  var varLines: [String] = []
  var keyLines: [String] = []

  for prop in insertProps {
    let base =
      prop.typeSyntax.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))
    if prop.hasDefault || prop.isOptional {
      varLines.append("  public var \(prop.name): \(base)? = nil")
    } else {
      varLines.append("  public var \(prop.name): \(base)")
    }
    keyLines.append(codingKeyLine(swiftName: prop.name, columnName: prop.columnName))
  }

  let vars = varLines.joined(separator: "\n")
  let keys = keyLines.joined(separator: "\n")

  return """
    public struct Insert: Encodable {
    \(raw: vars)
      public enum CodingKeys: String, CodingKey {
    \(raw: keys)
      }
    }
    """
}

private func makeUpdate(from props: [StoredPropertyInfo]) -> DeclSyntax {
  let updateProps = props.filter { !$0.isPrimaryKey }

  var varLines: [String] = []
  var keyLines: [String] = []

  for prop in updateProps {
    let base =
      prop.typeSyntax.trimmedDescription
      .trimmingCharacters(in: CharacterSet(charactersIn: "?"))
    varLines.append("  public var \(prop.name): \(base)? = nil")
    keyLines.append(codingKeyLine(swiftName: prop.name, columnName: prop.columnName))
  }

  let vars = varLines.joined(separator: "\n")
  let keys = keyLines.joined(separator: "\n")

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

private func makeColumnName(typeName: String, from props: [StoredPropertyInfo]) -> DeclSyntax {
  let columns = props
  let cases = columns.map {
    "  if erased == \\\(typeName).\($0.name) { return \"\($0.columnName)\" }"
  }.joined(separator: "\n")

  return """
    public static func columnName<V>(for keyPath: KeyPath<\(raw: typeName), V>) -> String {
      let erased = keyPath as AnyKeyPath
    \(raw: cases)
      preconditionFailure("Unknown column keypath on \(raw: typeName) — macro bug")
    }
    """
}

private func codingKeyLine(swiftName: String, columnName: String) -> String {
  swiftName == columnName
    ? "    case \(swiftName)"
    : "    case \(swiftName) = \"\(columnName)\""
}
