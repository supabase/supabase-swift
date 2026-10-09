//
//  PostgrestRawQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 02/10/26.
//

/// A read request whose response is text in a format other than JSON rows: CSV, GeoJSON, or an
/// execution plan.
///
/// Obtain one from ``_PostgrestQuery/csv()``, ``_PostgrestQuery/geojson()`` or
/// ``_PostgrestQuery/explain(analyze:verbose:settings:buffers:wal:format:)``. It is a dead end on
/// purpose. It has no ``_PostgrestQuery/stripNulls()`` and no way back to a ``_PostgrestQuery``, so
/// a request that asks for CSV and for stripped JSON nulls at once cannot be built.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestRawQuery: Sendable {
  let client: PostgrestClient
  let request: _PostgrestRequest

  /// Sends the request and returns the response body as text.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the body decoded as UTF-8.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<String> {
    try await request.execute(on: client) { String(decoding: $0, as: UTF8.self) }
  }
}
