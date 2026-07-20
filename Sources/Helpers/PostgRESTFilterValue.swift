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
