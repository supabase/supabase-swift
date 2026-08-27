//
//  CurlCommand.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
package import HTTPRuntime
package import HTTPTypes
import HTTPTypesFoundation

/// Renders an `HTTPRequest` and its body as a curl command — method, sorted
/// headers, escaped body, sorted query items. Mirrors the conventions of
/// `Sources/TestHelpers/URLRequestSnapshot.swift`'s `._curl` strategy for
/// `URLRequest`, implemented independently against `HTTPRequest` so this
/// target has no dependency on `TestHelpers`. `.file` request bodies aren't
/// rendered (no `--data` line) — out of scope for this helper's JSON-body
/// use case.
///
/// The body is a separate parameter because `HTTPTypes.HTTPRequest` models a
/// head only and carries no body.
package func curlCommand(for request: HTTPRequest, body: HTTPBody?) -> String {
  var components = ["curl"]

  switch request.method {
  case .get: break
  case .head: components.append("--head")
  default: components.append("--request \(request.method.rawValue)")
  }

  let sortedFields = request.headerFields.sorted { $0.name.rawName < $1.name.rawName }
  for field in sortedFields where field.name != .cookie {
    let escapedValue = field.value.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--header \"\(field.name.rawName): \(escapedValue)\"")
  }

  if case .data(let data) = body, let httpBody = String(data: data, encoding: .utf8) {
    var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
    escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--data \"\(escapedBody)\"")
  }

  if let cookie = request.headerFields[.cookie] {
    let escapedValue = cookie.replacingOccurrences(of: "\"", with: "\\\"")
    components.append("--cookie \"\(escapedValue)\"")
  }

  components.append("\"\(sortedQueryURLString(request.url))\"")

  return components.joined(separator: " \\\n\t")
}

/// `HTTPTypes.HTTPRequest.url` is optional. A nil URL renders as a visible
/// marker so a snapshot failure names the real problem.
private func sortedQueryURLString(_ url: URL?) -> String {
  guard let url else { return "<no URL>" }
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
    let queryItems = components.queryItems
  else {
    return url.absoluteString
  }
  components.queryItems = queryItems.sorted { $0.name < $1.name }
  return (components.url ?? url).absoluteString
}
