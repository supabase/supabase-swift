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
/// `url_session`. A plural `s` after the run belongs to it when the run ends in a known acronym:
/// `ownerIDs` becomes `owner_ids`, while `apiURLIsValid` becomes `api_url_is_valid`.
func camelToSnakeCase(_ name: String) -> String {
  var out = ""
  var previousWasUpper = false
  var run = ""
  for (index, character) in name.enumerated() {
    if character.isUppercase {
      let rest = name.dropFirst(index + 1)
      let nextIsLower = rest.first?.isLowercase ?? false
      run = previousWasUpper ? run + String(character) : String(character)
      // `IDs`: the `s` closes the run, so no word starts at `D`. `URLIsValid` is not a plural:
      // its run ends in `LI`, which is no acronym.
      let isPluralRun =
        previousWasUpper && rest.first == "s" && (rest.dropFirst().first?.isUppercase ?? true)
        && pluralAcronyms.contains { run.hasSuffix($0) }
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

private let pluralAcronyms = ["ID", "URL", "URI", "JWT", "OTP"]
