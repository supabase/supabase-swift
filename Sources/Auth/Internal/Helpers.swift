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

/// Reads the page number of every link in a `Link` response header, keyed by its `rel` value.
///
/// The header holds one link per relation, for example
/// `</admin/users?page=2>; rel="next", </admin/users?page=3>; rel="last"`.
///
/// Links that do not parse or carry no page number are skipped, so a header the client cannot read
/// costs the pagination metadata rather than failing a request that otherwise succeeded.
func parsePaginationLinks(_ header: String?) -> [String: Int] {
  guard let header,
    let pattern = try? NSRegularExpression(pattern: #"<([^>]+)>\s*;\s*rel="([^"]+)""#)
  else { return [:] }

  var pages: [String: Int] = [:]
  let matches = pattern.matches(in: header, range: NSRange(header.startIndex..., in: header))

  for match in matches {
    guard let uri = Range(match.range(at: 1), in: header).map({ String(header[$0]) }),
      let rel = Range(match.range(at: 2), in: header).map({ String(header[$0]) }),
      let page = URLComponents(string: uri)?.queryItems?.first(where: { $0.name == "page" })?.value,
      let pageNumber = Int(page)
    else { continue }

    pages[rel] = pageNumber
  }

  return pages
}
