//
//  OTelTraceContextProvider.swift
//  Examples
//
//  Implements TraceContextProvider using opentelemetry-swift.
//

import OpenTelemetryApi
import Supabase

/// Reads the active OpenTelemetry span from thread-local context and formats it as a W3C `traceparent` header.
///
/// Pass an instance to ``SupabaseClientOptions/GlobalOptions/tracePropagation`` when constructing `SupabaseClient`.
struct OTelTraceContextProvider: TraceContextProvider {
  func traceContext() -> [String: String] {
    guard let span = OpenTelemetry.instance.contextProvider.activeSpan,
      span.context.isValid
    else { return [:] }
    let ctx = span.context
    let flags = String(format: "%02x", ctx.traceFlags.rawValue)
    return ["traceparent": "00-\(ctx.traceId.hexString)-\(ctx.spanId.hexString)-\(flags)"]
  }
}
