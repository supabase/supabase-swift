//
//  PostgrestTelemetryIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 24/11/26.
//

#if OpenTelemetry
  import ConcurrencyExtras
  import Foundation
  import OpenTelemetryApi
  import OpenTelemetrySdk
  import Testing

  @testable import PostgREST

  /// The client span and duration metric of PostgREST calls against a live PostgREST: the status
  /// codes and the operation each method maps to are the server's, not a stub's. Runs only with
  /// the `OpenTelemetry` trait.
  @Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil)
  )
  struct PostgrestTelemetryIntegrationTests {
    let client = try! PostgrestClient(
      configuration: .init(
        url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
        headers: [.apikey: DotEnv.supabasePublishableKey]
      )
    )
    let recorder = IntegrationTelemetryRecorder()
    let url = URL(string: DotEnv.supabaseURL)!

    @Test
    func aFilteredSelectRecordsTheServerStatusAndARedactedURL() async throws {
      try await recorder.run {
        _ = try await client.from("users").select("username,status").eq(
          "username", value: "supabot"
        )
        .limit(1).execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.name == "GET /rest/v1/users")
      #expect(span.kind == .client)
      #expect(span.status == .unset)
      #expect(span.attributes["http.response.status_code"] == .int(200))
      #expect(span.attributes["server.address"] == .string(url.host!))
      #expect(span.attributes["supabase.postgrest.operation"] == .string("select"))
      #expect(span.attributes["supabase.postgrest.table"] == .string("users"))
      #expect(
        span.attributes["url.full"]
          == .string(
            "\(DotEnv.supabaseURL)/rest/v1/users?select=username%2Cstatus&username=REDACTED&limit=1"
          ))

      let point = try #require(recorder.durationPoints().only)
      #expect(point.count == 1)
      #expect(point.attributes["http.response.status_code"] == .int(200))
      #expect(point.attributes["url.full"] == nil)
    }

    @Test
    func anRPCCallRecordsTheFunction() async throws {
      try await recorder.run {
        _ = try await client.rpc("get_status", params: ["name_param": "supabot"]).execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.name == "POST /rest/v1/rpc/get_status")
      #expect(span.attributes["http.response.status_code"] == .int(200))
      #expect(span.attributes["supabase.postgrest.operation"] == .string("rpc"))
      #expect(span.attributes["supabase.postgrest.function"] == .string("get_status"))
    }

    @Test
    func aGetRPCCallRedactsEveryQueryValue() async throws {
      try await recorder.run {
        _ = try await client.rpc("get_status", params: ["name_param": "supabot"], get: true)
          .execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.name == "GET /rest/v1/rpc/get_status")
      #expect(span.attributes["http.response.status_code"] == .int(200))
      #expect(
        span.attributes["url.full"]
          == .string("\(DotEnv.supabaseURL)/rest/v1/rpc/get_status?name_param=REDACTED"))
    }

    @Test
    func anUpsertAndADeleteMapToTheirOperations() async throws {
      let id = UUID()
      try await recorder.run {
        try await client.from("todos")
          .upsert(["id": id.uuidString, "description": "span", "tags": "{}"])
          .execute()
        try await client.from("todos").delete().eq("id", value: id).execute()
      }

      let spans = recorder.spans
      #expect(spans.map(\.name) == ["POST /rest/v1/todos", "DELETE /rest/v1/todos"])
      #expect(spans.first?.attributes["supabase.postgrest.operation"] == .string("upsert"))
      #expect(spans.first?.attributes["http.response.status_code"] == .int(201))
      #expect(spans.last?.attributes["supabase.postgrest.operation"] == .string("delete"))
      #expect(spans.last?.attributes["http.response.status_code"] == .int(204))
    }

    @Test
    func aServerErrorMarksTheSpanAsFailed() async throws {
      await recorder.run {
        _ = try? await client.from("no_such_table").select().execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.attributes["http.response.status_code"] == .int(404))
      #expect(span.attributes["error.type"] == .string("404"))
      #expect(span.status == .error(description: "404"))
    }
  }

  /// Records the spans and metrics of the calls run through ``run(_:)``, with providers of its own
  /// instead of the global ones.
  final class IntegrationTelemetryRecorder: SpanExporter, MetricExporter, @unchecked Sendable {
    private let exportedSpans = LockIsolated<[SpanData]>([])
    private let exportedMetrics = LockIsolated<[MetricData]>([])
    private(set) var tracerProvider: TracerProviderSdk!
    private(set) var meterProvider: MeterProviderSdk!

    init() {
      tracerProvider = TracerProviderBuilder()
        .add(spanProcessor: SimpleSpanProcessor(spanExporter: self))
        .build()
      meterProvider = MeterProviderSdk.builder()
        .registerMetricReader(reader: PeriodicMetricReaderBuilder(exporter: self).build())
        .registerView(selector: InstrumentSelectorBuilder().build(), view: View.builder().build())
        .build()
    }

    func run<T>(_ operation: () async throws -> T) async rethrows -> T {
      let providers = PostgrestInstrumentation.Providers(
        tracerProvider: tracerProvider, meterProvider: meterProvider)
      return try await PostgrestInstrumentation.$providers.withValue(providers) {
        try await operation()
      }
    }

    /// The ended spans. The span processor exports on a queue, so this flushes it first.
    var spans: [SpanData] {
      tracerProvider.forceFlush()
      return exportedSpans.value
    }

    /// The points of the last cumulative export of `http.client.request.duration`.
    func durationPoints() -> [HistogramPointData] {
      _ = meterProvider.forceFlush()
      let metric = exportedMetrics.value.last { $0.name == "http.client.request.duration" }
      return metric?.data.points.compactMap { $0 as? HistogramPointData } ?? []
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
      exportedSpans.withValue { $0 += spans }
      return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) {}

    func export(metrics: [MetricData]) -> ExportResult {
      exportedMetrics.withValue { $0 += metrics }
      return .success
    }

    func export(metrics: [MetricData]) async -> ExportResult {
      exportedMetrics.withValue { $0 += metrics }
      return .success
    }

    func flush() -> ExportResult { .success }
    func shutdown() -> ExportResult { .success }

    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
      .cumulative
    }
  }

  extension Collection {
    /// The only element, or `nil` when there are none or more than one.
    fileprivate var only: Element? { count == 1 ? first : nil }
  }
#endif
