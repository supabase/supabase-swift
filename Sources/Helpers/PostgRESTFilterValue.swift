import Foundation

/// Characters that carry structural meaning in a PostgREST filter value list
/// (e.g. `in.(a,b,c)`) and therefore require the value to be double-quoted.
private let postgrestReservedCharacters: Set<Character> = [",", "(", ")", "\"", "\\"]

/// Whether `value` must be double-quoted when embedded in a PostgREST filter,
/// i.e. it contains a reserved character or has surrounding whitespace.
package func postgrestFilterValueNeedsQuoting(_ value: String) -> Bool {
  value.contains(where: postgrestReservedCharacters.contains)
    || value != value.trimmingCharacters(in: .whitespaces)
}

/// Escapes a raw filter value for safe inclusion in a PostgREST filter such as
/// `in.(...)`. Values containing reserved characters (`,`, `(`, `)`, `"`, `\`)
/// or surrounding whitespace are double-quoted, with `\` and `"` backslash-escaped.
package func escapePostgRESTFilterValue(_ raw: String) -> String {
  guard postgrestFilterValueNeedsQuoting(raw) else { return raw }
  let escaped = raw.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}

/// Characters that carry structural meaning inside a PostgREST array literal
/// (e.g. `cs.{a,b}`) and therefore require the element to be double-quoted.
private let postgrestArrayLiteralReservedCharacters: Set<Character> = [
  ",", "{", "}", "\"", "\\",
]

/// Whether `element` must be double-quoted when embedded in a PostgREST array
/// literal, i.e. it is empty, equals `NULL`, contains a reserved character, or
/// has surrounding whitespace.
package func postgrestArrayLiteralElementNeedsQuoting(_ element: String) -> Bool {
  element.isEmpty
    || element.caseInsensitiveCompare("NULL") == .orderedSame
    || element.contains(where: postgrestArrayLiteralReservedCharacters.contains)
    || element != element.trimmingCharacters(in: .whitespaces)
}

/// Escapes a raw value for safe inclusion as an element of a PostgREST array
/// literal such as `cs.{...}`. Elements needing quoting are double-quoted, with
/// `\` and `"` backslash-escaped.
package func escapePostgRESTArrayLiteralElement(_ raw: String) -> String {
  guard postgrestArrayLiteralElementNeedsQuoting(raw) else { return raw }
  let escaped = raw.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(escaped)\""
}
