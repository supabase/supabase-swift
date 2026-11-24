//
//  PostgrestInstrumentation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation
import HTTPTypes
import Helpers

#if OpenTelemetry
  import OpenTelemetryApi
  import OpenTelemetrySdk
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
    clock: any Swift.Clock<Duration>,
    send: () async throws -> (HTTPTypes.HTTPResponse, Data)
  ) async throws -> (HTTPTypes.HTTPResponse, Data) {
    #if OpenTelemetry
      guard let url = request.url else { return try await send() }
      return try await PostgrestInstrumentation.instrument(
        call, method: request.method, url: url, clock: clock, send: send)
    #else
      try await send()
    #endif
  }
}

#if OpenTelemetry
  /// The client span and duration metric of a PostgREST call, per the OpenTelemetry HTTP client
  /// conventions plus the `supabase.postgrest.*` attributes.
  ///
  /// Telemetry never carries a customer's data: `url.full` goes through
  /// ``PostgrestTelemetry/redactedURL(_:)`` and the metric carries no URL.
  enum PostgrestInstrumentation {
    /// The tracer and meter providers a call records to.
    struct Providers: @unchecked Sendable {
      var tracerProvider: any TracerProvider
      var meterProvider: any MeterProvider
    }

    /// Overrides the global providers for the calls in a task, so a test can record without
    /// registering a provider for the whole process.
    @TaskLocal static var providers: Providers?

    static let scopeName = "supabase.postgrest"

    /// The bucket boundaries the HTTP semantic conventions advise for
    /// `http.client.request.duration`. The SDK's default boundaries are sized for milliseconds.
    static let durationBucketBoundaries: [Double] = [
      0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10,
    ]

    static func instrument(
      _ call: PostgrestCall,
      method: HTTPTypes.HTTPRequest.Method,
      url: URL,
      clock: any Swift.Clock<Duration>,
      send: () async throws -> (HTTPTypes.HTTPResponse, Data)
    ) async throws -> (HTTPTypes.HTTPResponse, Data) {
      let providers =
        providers
        ?? Providers(
          tracerProvider: OpenTelemetry.instance.tracerProvider,
          meterProvider: OpenTelemetry.instance.meterProvider)

      var attributes = call.attributes
      attributes["http.request.method"] = .string(method.rawValue)
      attributes["server.address"] = .string(url.host ?? "")
      attributes["server.port"] = .int(url.port ?? (url.scheme == "http" ? 80 : 443))

      let span = providers.tracerProvider
        .get(instrumentationName: scopeName, instrumentationVersion: version)
        .spanBuilder(spanName: "\(method.rawValue) \(url.path)")
        .setSpanKind(spanKind: .client)
        .startSpan()
      // Redacting the URL costs a parse, so a span that does not record skips it.
      if span.isRecording {
        span.setAttributes(attributes)
        span.setAttribute(key: "url.full", value: .string(PostgrestTelemetry.redactedURL(url)))
      }

      let elapsed = stopwatch(on: clock)
      let result: Result<(HTTPTypes.HTTPResponse, Data), any Error>
      do {
        // A span that does not record, such as the one the default no-op tracer returns, has
        // random IDs and is not sampled. Naming it in `traceparent` would turn off server-side
        // sampling, so the app's own active span, if any, is sent instead.
        if span.isRecording {
          let context = span.context
          let traceParent =
            "00-\(context.traceId.hexString)-\(context.spanId.hexString)-\(context.traceFlags.hexString)"
          result = .success(
            try await ClientSpanContext.$traceParent.withValue(traceParent) { try await send() })
        } else {
          result = .success(try await send())
        }
      } catch {
        result = .failure(error)
      }
      let seconds = elapsed()

      var outcome: [String: AttributeValue] = [:]
      switch result {
      case .success(let (response, _)):
        let statusCode = response.status.code
        outcome["http.response.status_code"] = .int(statusCode)
        if statusCode >= 400 { outcome["error.type"] = .string(String(statusCode)) }
      case .failure(let error):
        outcome["error.type"] = .string(PostgrestTelemetry.errorType(of: error))
      }
      if case .string(let errorType) = outcome["error.type"] {
        span.status = .error(description: errorType)
      }
      span.setAttributes(outcome)
      span.end()

      var metricAttributes = attributes.merging(outcome) { $1 }
      metricAttributes["url.scheme"] = .string(url.scheme ?? "")
      var histogram = requestDuration(providers.meterProvider)
      histogram.record(value: seconds, attributes: metricAttributes)
      return try result.get()
    }

    /// Starts timing on `clock`. The returned closure gives the seconds since.
    private static func stopwatch<C: Swift.Clock<Duration>>(on clock: C) -> () -> Double {
      let start = clock.now
      return {
        let elapsed = start.duration(to: clock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
      }
    }

    /// `http.client.request.duration`, in seconds.
    ///
    /// The metrics API cannot set an instrument's unit or description
    /// (open-telemetry/opentelemetry-swift#1315), so they are set only when the app uses the
    /// official SDK, whose builder can.
    private static func requestDuration(_ meterProvider: any MeterProvider) -> any DoubleHistogram {
      let builder = meterProvider.meterBuilder(name: scopeName)
        .setInstrumentationVersion(instrumentationVersion: version)
        .build()
        .histogramBuilder(name: "http.client.request.duration")
        .setExplicitBucketBoundariesAdvice(durationBucketBoundaries)
      guard let sdkBuilder = builder as? DoubleHistogramMeterBuilderSdk else {
        return builder.build()
      }
      return sdkBuilder.setUnit("s").setDescription("Duration of HTTP client requests.").build()
    }
  }

  extension PostgrestCall {
    /// The `supabase.postgrest.*` attributes, shared by the span and the measurement.
    fileprivate var attributes: [String: AttributeValue] {
      var attributes: [String: AttributeValue] = [
        "supabase.postgrest.operation": .string(operation.rawValue)
      ]
      if let table { attributes["supabase.postgrest.table"] = .string(table) }
      if let function { attributes["supabase.postgrest.function"] = .string(function) }
      return attributes
    }
  }
#endif
