import Foundation

/// Extracts parameters encoded in the URL both in the query and fragment.
func extractParams(from url: URL) -> [String: String] {
  guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return [:]
  }

  var result: [String: String] = [:]

  if let fragment = components.percentEncodedFragment {
    for (name, value) in parseFormEncodedPairs(fragment) {
      result[name] = value
    }
  }

  if let query = components.percentEncodedQuery {
    for (name, value) in parseFormEncodedPairs(query) {
      result[name] = value
    }
  }

  return result
}

private func parseFormEncodedPairs(_ percentEncodedString: String) -> [(
  name: String, value: String
)] {
  percentEncodedString
    .split(separator: "&")
    .compactMap { pair in
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[1].isEmpty else { return nil }
      return (decodeFormComponent(parts[0]), decodeFormComponent(parts[1]))
    }
}

private func decodeFormComponent(_ component: Substring) -> String {
  let plusDecoded = component.replacingOccurrences(of: "+", with: " ")
  return plusDecoded.removingPercentEncoding ?? plusDecoded
}
