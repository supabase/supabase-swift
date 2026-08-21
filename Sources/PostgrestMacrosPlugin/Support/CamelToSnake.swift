//
//  CamelToSnake.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

/// Converts a Swift property name to its snake_case database column name.
///
/// `isDone` becomes `is_done`; `dueDate` becomes `due_date`; an already-lowercase name is unchanged.
/// A run of capitals is one word, so `htmlURL` becomes `html_url` and `urlSession` stays
/// `url_session`.
func camelToSnakeCase(_ name: String) -> String {
  var out = ""
  var previousWasUpper = false
  for (index, character) in name.enumerated() {
    if character.isUppercase {
      let nextIsLower = name.dropFirst(index + 1).first?.isLowercase ?? false
      if index > 0, !previousWasUpper || nextIsLower {
        out.append("_")
      }
      out.append(Character(character.lowercased()))
      previousWasUpper = true
    } else {
      out.append(character)
      previousWasUpper = false
    }
  }
  return out
}
