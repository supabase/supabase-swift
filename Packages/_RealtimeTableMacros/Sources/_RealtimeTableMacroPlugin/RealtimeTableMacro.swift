import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct RealtimeTableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw MacroError(message: "@RealtimeTable can only be applied to structs")
    }

    guard let args = node.arguments?.as(LabeledExprListSyntax.self),
          let schemaExpr = args.first(where: { $0.label?.text == "schema" })?.expression,
          let tableExpr = args.first(where: { $0.label?.text == "table" })?.expression,
          let schema = schemaExpr.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
          let table = tableExpr.as(StringLiteralExprSyntax.self)?.representedLiteralValue
    else {
      throw MacroError(message: "@RealtimeTable requires schema: and table: arguments")
    }

    let typeName = structDecl.name.text
    let columnNames = extractColumnNames(from: structDecl)

    var caseLines: [String] = []
    for (prop, column) in columnNames {
      caseLines.append("    case \\\(typeName).\(prop): return \"\(column)\"")
    }
    let cases = caseLines.joined(separator: "\n")

    let extensionSource = """
    extension \(typeName): RealtimeTable {
      static let schema: String = "\(schema)"
      static let tableName: String = "\(table)"
      static func columnName<V>(for keyPath: KeyPath<\(typeName), V>) -> String {
        switch keyPath {
    \(cases)
        default: fatalError("Unknown keypath for RealtimeTable \\(keyPath)")
        }
      }
    }
    """

    let extensionDecl = try ExtensionDeclSyntax("\(raw: extensionSource)")
    return [extensionDecl]
  }

  private static func extractColumnNames(from decl: StructDeclSyntax) -> [(String, String)] {
    var codingKeyMap: [String: String] = [:]
    for member in decl.memberBlock.members {
      if let enumDecl = member.decl.as(EnumDeclSyntax.self),
         enumDecl.name.text == "CodingKeys" {
        for enumMember in enumDecl.memberBlock.members {
          if let caseDecl = enumMember.decl.as(EnumCaseDeclSyntax.self) {
            for element in caseDecl.elements {
              let propName = element.name.text
              if let rawValue = element.rawValue?.value
                .as(StringLiteralExprSyntax.self)?.representedLiteralValue {
                codingKeyMap[propName] = rawValue
              } else {
                codingKeyMap[propName] = propName
              }
            }
          }
        }
      }
    }

    var result: [(String, String)] = []
    for member in decl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self),
            varDecl.bindingSpecifier.text == "var" else { continue }
      for binding in varDecl.bindings {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
          continue
        }
        // Skip computed properties (they have an accessor block)
        if binding.accessorBlock != nil { continue }
        let column: String
        if let mapped = codingKeyMap[name] {
          column = mapped
        } else if codingKeyMap.isEmpty {
          column = camelToSnake(name)
        } else {
          column = name
        }
        result.append((name, column))
      }
    }
    return result
  }

  private static func camelToSnake(_ s: String) -> String {
    var result = ""
    for (i, char) in s.enumerated() {
      if char.isUppercase && i > 0 {
        result.append("_")
        result.append(char.lowercased())
      } else {
        result.append(char)
      }
    }
    return result
  }
}

struct MacroError: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}

@main struct _RealtimeTableMacroPlugin: CompilerPlugin {
  var providingMacros: [any Macro.Type] = [RealtimeTableMacro.self]
}
