import Foundation
import HTTPTypes
import IssueReporting

let base64UrlRegex = try! NSRegularExpression(
  pattern: "^([a-z0-9_-]{4})*($|[a-z0-9_-]{3}$|[a-z0-9_-]{2}$)", options: .caseInsensitive)

/// Checks that the value somewhat looks like a JWT, does not do any additional parsing or verification.
func isJWT(_ value: String) -> Bool {
  var token = value

  if token.hasPrefix("Bearer ") {
    token = String(token.dropFirst("Bearer ".count))
  }

  token = token.trimmingCharacters(in: .whitespacesAndNewlines)

  guard !token.isEmpty else {
    return false
  }

  let parts = token.split(separator: ".")

  guard parts.count == 3 else {
    return false
  }

  for part in parts {
    if part.count < 4 || !isBase64Url(String(part)) {
      return false
    }
  }

  return true
}

func isBase64Url(_ value: String) -> Bool {
  let range = NSRange(location: 0, length: value.utf16.count)
  return base64UrlRegex.firstMatch(in: value, options: [], range: range) != nil
}

func checkAuthorizationHeader(
  _ headers: HTTPFields,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  guard let authorization = headers[.authorization] else { return }

  if !isJWT(authorization) {
    reportIssue(
      "Authorization header does not contain a JWT",
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
}
