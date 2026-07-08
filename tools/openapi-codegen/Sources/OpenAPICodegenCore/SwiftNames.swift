//
//  SwiftNames.swift
//

enum SwiftNames {

  static let reservedWords: Set<String> = [
    "public", "private", "internal", "fileprivate", "open",
    "self", "Self", "class", "struct", "enum", "protocol",
    "default", "for", "in", "if", "else", "switch", "case",
    "return", "func", "var", "let", "import", "extension", "static",
    "true", "false", "nil", "is", "as", "guard", "where", "continue", "break",
    "operator", "typealias", "associatedtype", "subscript", "init", "deinit",
  ]

  static func typeName(_ raw: String) -> String {
    let camel = camelCased(raw)
    guard let first = camel.first else { return camel }
    return first.uppercased() + camel.dropFirst()
  }

  static func propertyName(_ raw: String) -> String {
    escape(camelCased(raw))
  }

  private static func camelCased(_ raw: String) -> String {
    let parts = raw.split(whereSeparator: { $0 == "_" || $0 == "-" })
    guard let first = parts.first else { return raw }
    let rest = parts.dropFirst().map { part -> String in
      guard let firstCharacter = part.first else { return String(part) }
      return firstCharacter.uppercased() + part.dropFirst()
    }
    return ([String(first)] + rest).joined()
  }

  private static func escape(_ identifier: String) -> String {
    reservedWords.contains(identifier) ? "`\(identifier)`" : identifier
  }

  static func typeReference(_ type: IRType, isOptional: Bool) -> String {
    let base = baseTypeReference(type)
    return isOptional ? "\(base)?" : base
  }

  static func baseTypeReference(_ type: IRType) -> String {
    switch type {
    case .string: return "String"
    case .integer: return "Int"
    case .number: return "Double"
    case .boolean: return "Bool"
    case .array(let element): return "[\(baseTypeReference(element))]"
    case .schemaRef(let name): return typeName(name)
    case .freeform: return "[String: JSONValue]"
    }
  }
}
