import Foundation

#if OpenTelemetry
  import OpenTelemetryApi
#endif

/// Builds and injects the W3C `traceparent` header from the currently active OpenTelemetry span.
///
/// Requires the `OpenTelemetry` package trait; compiles to a no-op when the trait is disabled,
/// so ``SupabaseClientOptions/GlobalOptions/tracePropagation`` is always safe to set regardless
/// of whether the trait is enabled.
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
