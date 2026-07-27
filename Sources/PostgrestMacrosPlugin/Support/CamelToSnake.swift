/// Converts a camelCase identifier to snake_case.
/// Examples: "isComplete" → "is_complete", "userId" → "user_id", "id" → "id"
func camelToSnake(_ input: String) -> String {
  var result = ""
  for (i, char) in input.enumerated() {
    if char.isUppercase && i > 0 {
      result += "_"
    }
    result += char.lowercased()
  }
  return result
}
