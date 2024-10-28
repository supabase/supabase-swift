import Foundation
import Helpers

/// Extracts parameters encoded in the URL both in the query and fragment.
func extractParams(from url: URL) -> [String: String] {
  guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return [:]
  }

  var result: [String: String] = [:]

  if let fragment = components.fragment {
    let items = extractParams(from: fragment)
    for item in items {
      result[item.name] = item.value
    }
  }

  if let items = components.queryItems {
    for item in items {
      result[item.name] = item.value
    }
  }

  return result
}

private func extractParams(from fragment: String) -> [URLQueryItem] {
  let components =
    fragment
    .split(separator: "&")
    .map { $0.split(separator: "=") }

  return
    components
    .compactMap {
      $0.count == 2
        ? URLQueryItem(name: String($0[0]), value: String($0[1]))
        : nil
    }
}
