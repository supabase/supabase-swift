//
//  PostgrestRawQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 02/10/26.
//

/// A read request whose response is text in a format other than JSON rows: CSV, GeoJSON, or an
/// execution plan.
///
/// Obtain one from ``PostgrestQuery/csv()``, ``PostgrestQuery/geojson()`` or
/// ``PostgrestQuery/explain(analyze:verbose:settings:buffers:wal:format:)``. It is a dead end on
/// purpose. It has no ``PostgrestQuery/stripNulls()`` and no way back to a ``PostgrestQuery``, so
/// a request that asks for CSV and for stripped JSON nulls at once cannot be built.
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
public struct PostgrestRawQuery: Sendable {
  let client: PostgrestClient
  let request: PostgrestRequest

  /// Sends the request and returns the response body as text.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the body decoded as UTF-8.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<String> {
    try await request.execute(on: client) { data, _ in String(decoding: data, as: UTF8.self) }
  }
}
