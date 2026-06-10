//
//  TraceContext.swift
//  Supabase
//
//  Created by Guilherme Souza on 10/06/26.
//

/// Provides W3C trace context headers to inject into every outgoing HTTP request.
///
/// Implement this protocol using any OpenTelemetry-compatible library and pass the instance
/// via ``SupabaseClientOptions/GlobalOptions/tracePropagation``.
///
/// Example using opentelemetry-swift:
///
/// ```swift
/// import OpenTelemetryApi
///
/// struct OTelTraceContextProvider: TraceContextProvider {
///   func traceContext() -> [String: String] {
///     guard let span = OpenTelemetry.instance.contextProvider.activeSpan else { return [:] }
///     let traceId = span.context.traceId.hexString
///     let spanId = span.context.spanId.hexString
///     return ["traceparent": "00-\(traceId)-\(spanId)-01"]
///   }
/// }
/// ```
public protocol TraceContextProvider: Sendable {
  /// Returns the trace context headers to inject into the current request.
  ///
  /// Called once per outgoing HTTP request. Return an empty dictionary when no active span exists.
  func traceContext() -> [String: String]
}
