#if OpenTelemetry
  import OpenTelemetryApi
#endif

/// Builds the W3C `traceparent` header from the currently active OpenTelemetry span.
///
/// Applied unconditionally by `SupabaseClient` via `TraceContextMiddleware` — the `OpenTelemetry`
/// package trait is the sole on/off switch. Compiles to a no-op when the trait is disabled, and
/// returns `nil` at runtime when there's no active span.
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
  /// The `traceparent` header value for the active OpenTelemetry span, or `nil` if there is none.
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
