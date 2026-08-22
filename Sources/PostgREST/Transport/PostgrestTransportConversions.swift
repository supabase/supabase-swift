//
//  PostgrestTransportConversions.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

import Foundation
import HTTPRuntime
import HTTPTypes

/// Maps a method across the two spellings.
///
/// Written as an exhaustive switch rather than `HTTPTypes.HTTPRequest.Method(rawValue:)`, which is
/// failable: every case here is known good, so there is no error path to invent, and adding a verb
/// to `HTTPRuntime.HTTPMethod` becomes a compile error instead of a runtime `nil`.
func postgrestHTTPMethod(
  from method: HTTPRuntime.HTTPMethod
) -> HTTPTypes.HTTPRequest.Method {
  switch method {
  case .get: .get
  case .post: .post
  case .put: .put
  case .patch: .patch
  case .delete: .delete
  case .head: .head
  }
}

/// Maps a method back, for a transport handing a request to `HTTPRuntime`.
///
/// - Throws: `HTTPRuntime.HTTPError.transport` for a method `HTTPRuntime` has no case for. Only
///   reachable for verbs PostgREST never sends, such as `OPTIONS`.
func postgrestHTTPMethod(
  from method: HTTPTypes.HTTPRequest.Method
) throws -> HTTPRuntime.HTTPMethod {
  guard let mapped = HTTPRuntime.HTTPMethod(rawValue: method.rawValue) else {
    throw HTTPRuntime.HTTPError.transport(PostgrestUnsupportedMethod(method: method.rawValue))
  }
  return mapped
}

/// Thrown for an HTTP method `HTTPRuntime` cannot express.
struct PostgrestUnsupportedMethod: Error, Sendable, CustomStringConvertible {
  let method: String

  var description: String { "HTTPRuntime has no case for the HTTP method \(method)." }
}

/// Rebuilds a URL from the pseudo-header fields, without decoding the path or query.
///
/// - Throws: `URLError(.badURL)` when a pseudo-header field is missing or the pieces do not form a
///   URL. Concatenation is deliberate: `URLComponents` would re-encode the query, and PostgREST
///   needs an encoding stricter than Foundation's default.
func postgrestRequestURL(from request: HTTPTypes.HTTPRequest) throws -> URL {
  guard let scheme = request.scheme,
    let authority = request.authority,
    let path = request.path,
    let url = URL(string: "\(scheme)://\(authority)\(path)")
  else {
    throw URLError(.badURL)
  }
  return url
}

/// Converts header fields to the dictionary `HTTPRuntime` uses.
///
/// Repeated field names are joined with `", "` per RFC 9110 section 5.3, which is what makes a
/// dictionary a lossless representation for every field PostgREST sends or receives.
///
/// Names keep the casing they were written with — `rawName`, not `canonicalName`, which lowercases
/// for HTTP/2. Every consumer downstream matches case-insensitively, so the choice only affects
/// what a log or a recorded request looks like, and `Prefer` reads better there than `prefer`.
func postgrestHeaderDictionary(from fields: HTTPTypes.HTTPFields) -> [String: String] {
  var headers: [String: String] = [:]
  for field in fields {
    let name = field.name.rawName
    // Match case-insensitively, or `Prefer` and `prefer` become two entries and one of them is
    // dropped by whichever consumer looks the header up.
    let key = headers.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    if let existing = headers[key] {
      headers[key] = "\(existing), \(field.value)"
    } else {
      headers[key] = field.value
    }
  }
  return headers
}

/// Converts a header dictionary to header fields.
///
/// A name `HTTPTypes` rejects is dropped. That is unreachable for anything PostgREST builds, and
/// the alternative — failing the whole request over one malformed name — is worse for a caller who
/// set an odd header deliberately.
func postgrestHeaderFields(from headers: [String: String]) -> HTTPTypes.HTTPFields {
  var fields = HTTPTypes.HTTPFields()
  for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
    guard let fieldName = HTTPTypes.HTTPField.Name(name) else { continue }
    fields[fieldName] = value
  }
  return fields
}

/// Converts a response head to the `HTTPTypes` spelling.
func postgrestHTTPResponse(
  from head: HTTPRuntime.HTTPResponseHead
) -> HTTPTypes.HTTPResponse {
  HTTPTypes.HTTPResponse(
    status: .init(code: head.status),
    headerFields: postgrestHeaderFields(from: head.headers)
  )
}
