//
//  PostgrestTelemetry.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension _PostgrestRequest {
  /// Runs `send` and, with the `OpenTelemetry` package trait, records it as one client span and one
  /// `http.client.request.duration` measurement. Without the trait it only runs `send`.
  ///
  /// - Parameters:
  ///   - request: The request `send` sends, before the middlewares run.
  ///   - clock: Times the duration measurement.
  ///   - send: Sends the request, retries included.
  /// - Returns: The response and body `send` returns.
  /// - Throws: The error `send` throws.
  func instrument(
    _ request: HTTPTypes.HTTPRequest,
    clock: any Clock<Duration>,
    send: () async throws -> (HTTPTypes.HTTPResponse, Data)
  ) async throws -> (HTTPTypes.HTTPResponse, Data) {
    #if OpenTelemetry
      guard let url = request.url else { return try await send() }
      return try await PostgrestInstrumentation.instrument(
        call, method: request.method, url: url,
        stopwatch: { PostgrestTelemetry.stopwatch(on: clock) }, send: send)
    #else
      try await send()
    #endif
  }
}

/// The parts of a PostgREST call's telemetry that hold no OpenTelemetry type. This file does not
/// import OpenTelemetrySdk, whose `Clock` would hide the standard library's.
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

  /// `url` as `url.full` records it: every query value is `REDACTED`, and user info and fragment
  /// are dropped. PostgREST puts column filters and their values in the query string, so a value
  /// can be a customer's data.
  ///
  /// The values of ``shapingKeys`` are kept only when `keepingShapingValues` is `true`. An RPC
  /// call passes `false`: its query can carry the function's arguments.
  ///
  /// Keys and kept values stay in their percent-encoded wire form. A key with no `=` has no value
  /// to redact and is kept as sent.
  static func redactedURL(_ url: URL, keepingShapingValues: Bool) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return ""
    }
    components.user = nil
    components.password = nil
    components.fragment = nil
    components.percentEncodedQueryItems = components.percentEncodedQueryItems?.map {
      (keepingShapingValues && shapingKeys.contains($0.name)) || $0.value == nil
        ? $0 : URLQueryItem(name: $0.name, value: "REDACTED")
    }
    if components.percentEncodedQuery?.isEmpty == true { components.percentEncodedQuery = nil }
    return components.string ?? ""
  }

  /// Starts timing on `clock`. The returned closure gives the seconds since.
  static func stopwatch(on clock: some Clock<Duration>) -> () -> Double {
    let start = clock.now
    return {
      let elapsed = start.duration(to: clock.now).components
      return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
  }
}
