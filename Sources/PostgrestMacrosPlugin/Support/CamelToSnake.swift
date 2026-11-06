//
//  CamelToSnake.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

/// Converts a Swift property name to its snake_case database column name.
///
/// `isDone` becomes `is_done`; `dueDate` becomes `due_date`; an already-lowercase name is
/// unchanged. A run of capitals is one word, so `htmlURL` becomes `html_url` and `urlSession` stays
/// `url_session`. A plural `s` after the run belongs to it: `ownerIDs` becomes `owner_ids`.
func camelToSnakeCase(_ name: String) -> String {
  var out = ""
  var previousWasUpper = false
  for (index, character) in name.enumerated() {
    if character.isUppercase {
      let rest = name.dropFirst(index + 1)
      let nextIsLower = rest.first?.isLowercase ?? false
      // `IDs`: the `s` closes the run, so no word starts at `D`.
      let isPluralRun =
        previousWasUpper && rest.first == "s" && (rest.dropFirst().first?.isUppercase ?? true)
      if index > 0, !previousWasUpper || (nextIsLower && !isPluralRun) {
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
