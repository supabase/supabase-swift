import Foundation

/// Extracts parameters encoded in the URL both in the query and fragment.
func extractParams(from url: URL) -> [String: String] {
  guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return [:]
  }

  var result: [String: String] = [:]

  if let fragment = components.percentEncodedFragment {
    for item in extractParams(from: fragment) {
      result[item.name] = item.value
    }
  }

  if let query = components.percentEncodedQuery {
    for item in extractParams(from: query) {
      result[item.name] = item.value
    }
  }

  return result
}

private func extractParams(from percentEncodedString: String) -> [URLQueryItem] {
  percentEncodedString
    .split(separator: "&")
    .map { pair in
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = decodeFormComponent(parts[0])
      let value = parts.count == 2 ? decodeFormComponent(parts[1]) : ""
      return URLQueryItem(name: name, value: value)
    }
}

private func decodeFormComponent(_ component: Substring) -> String {
  let plusDecoded = component.replacingOccurrences(of: "+", with: " ")
  return plusDecoded.removingPercentEncoding ?? plusDecoded
}
