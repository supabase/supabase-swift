//
//  CurlCommand.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
package import HTTPRuntime

/// Renders an `HTTPRequest` as a curl command — method, sorted headers,
/// escaped body, sorted query items. Mirrors the conventions of
/// `Sources/TestHelpers/URLRequestSnapshot.swift`'s `._curl` strategy for
/// `URLRequest`, implemented independently against `HTTPRequest` so this
/// target has no dependency on `TestHelpers`. `.file` request bodies aren't
/// rendered (no `--data` line) — out of scope for this helper's JSON-body
/// use case.
package func curlCommand(for request: HTTPRequest) -> String {
  var components = ["curl"]

  switch request.method {
  case .get: break
  case .head: components.append("--head")
  default: components.append("--request \(request.method.rawValue)")
  }

  for field in request.headers.keys.sorted() where field != "Cookie" {
    let escapedValue = request.headers[field]!.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--header \"\(field): \(escapedValue)\"")
  }

  if case .data(let data) = request.body, let httpBody = String(data: data, encoding: .utf8) {
    var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
    escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--data \"\(escapedBody)\"")
  }

  if let cookie = request.headers["Cookie"] {
    let escapedValue = cookie.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--cookie \"\(escapedValue)\"")
  }

  components.append("\"\(sortedQueryURL(request.url).absoluteString)\"")

  return components.joined(separator: " \\\n\t")
}

private func sortedQueryURL(_ url: URL) -> URL {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
    let queryItems = components.queryItems
  else {
    return url
  }
  components.queryItems = queryItems.sorted { $0.name < $1.name }
  return components.url ?? url
}
