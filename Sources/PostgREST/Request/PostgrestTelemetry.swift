//
//  PostgrestTelemetry.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The parts of a PostgREST call's telemetry that hold no OpenTelemetry type.
enum PostgrestTelemetry {
  /// The query keys whose values only shape the result, so `url.full` keeps them.
  private static let shapingKeys: Set<String> = ["select", "order", "limit", "offset"]

  /// The `error.type` of a call that got no response: the error's qualified type name.
  ///
  /// A `URLError` can arrive bridged to `NSError`, whose type name says nothing, so it is named
  /// by the `URLError` type.
  static func errorType(of error: any Error) -> String {
    String(reflecting: error is URLError ? URLError.self : type(of: error))
  }

  /// `url` as `url.full` records it: every query value is `REDACTED` except those of
  /// ``shapingKeys``, and user info and fragment are dropped. PostgREST puts column filters and
  /// their values in the query string, so a value can be a customer's data.
  ///
  /// Keys and kept values stay in their percent-encoded wire form. A key with no `=` has no value
  /// to redact and is kept as sent.
  static func redactedURL(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return ""
    }
    components.user = nil
    components.password = nil
    components.fragment = nil
    components.percentEncodedQueryItems = components.percentEncodedQueryItems?.map {
      shapingKeys.contains($0.name) || $0.value == nil
        ? $0 : URLQueryItem(name: $0.name, value: "REDACTED")
    }
    if components.percentEncodedQuery?.isEmpty == true { components.percentEncodedQuery = nil }
    return components.string ?? ""
  }
}
