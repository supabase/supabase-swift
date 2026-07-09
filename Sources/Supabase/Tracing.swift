import Foundation

#if OpenTelemetry
  import OpenTelemetryApi
#endif

/// Builds and injects the W3C `traceparent` header from the currently active OpenTelemetry span.
///
/// Applied unconditionally by `SupabaseClient` — the `OpenTelemetry` package trait is the sole
/// on/off switch. Compiles to a no-op when the trait is disabled, and no-ops at runtime when
/// there's no active span, so calling ``inject(into:)`` is always safe.
///
/// Not applied to `FunctionsClient._invokeWithStreamedResponse`, which uses its own `URLSession`
/// outside `SupabaseClient`'s fetch pipeline (same pre-existing exception as auth header injection).
///
/// To enable, add the trait to your dependency declaration:
///
/// ```swift
/// .package(
///   url: "https://github.com/supabase/supabase-swift.git",
///   from: "2.0.0",
///   traits: ["OpenTelemetry"]
/// )
/// ```
enum TraceContext {
  /// Sets the `traceparent` header on `request` from the active OpenTelemetry span, if any.
  static func inject(into request: URLRequest) -> URLRequest {
    guard let traceparent = traceParentHeader() else { return request }
    var request = request
    request.setValue(traceparent, forHTTPHeaderField: "traceparent")
    return request
  }

  static func traceParentHeader() -> String? {
    #if OpenTelemetry
      guard let context = OpenTelemetry.instance.contextProvider.activeSpan?.context else {
        return nil
      }
      return
        "00-\(context.traceId.hexString)-\(context.spanId.hexString)-\(context.traceFlags.hexString)"
    #else
      return nil
    #endif
  }
}
