//
//  PostgrestInstrumentationTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

#if OpenTelemetry
  import ConcurrencyExtras
  import Foundation
  import HTTPTypes
  import Helpers
  import OpenTelemetryApi
  import OpenTelemetrySdk
  import TestHelpers
  import Testing

  @_spi(Experimental) @testable import PostgREST

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  /// Collects the spans and metrics a ``PostgrestClient`` emits, through providers this test owns
  /// instead of the global ones, so the tests can run in parallel with suites that expect no
  /// tracer to be registered.
  final class TelemetryRecorder: @unchecked Sendable {
    let spanExporter = InMemorySpanExporter()
    let metricExporter = InMemoryMetricExporter()
    let tracerProvider: TracerProviderSdk
    let meterProvider: MeterProviderSdk

    init() {
      tracerProvider = TracerProviderBuilder()
        .add(spanProcessor: SimpleSpanProcessor(spanExporter: spanExporter))
        .build()
      meterProvider = MeterProviderSdk.builder()
        .registerMetricReader(reader: PeriodicMetricReaderBuilder(exporter: metricExporter).build())
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

    /// Runs `work` with an app span active, the way an app traces a screen, and returns that
    /// span's context. `@concurrent` because `withActiveSpan` is.
    @concurrent
    func inParentSpan(_ work: @Sendable () async throws -> Void) async throws -> SpanContext {
      let parent = tracerProvider.get(instrumentationName: "app")
        .spanBuilder(spanName: "screen").startSpan()
      defer { parent.end() }
      try await OpenTelemetry.instance.contextProvider.withActiveSpan(parent) { try await work() }
      return parent.context
    }

    /// The ended spans. The span processor exports on a queue, so this flushes it first.
    var spans: [SpanData] {
      tracerProvider.forceFlush()
      return spanExporter.spans.value
    }

    /// The last export of `http.client.request.duration`, after a flush. The exporter is
    /// cumulative, so the last export holds every call so far.
    func durationMetric() -> MetricData? {
      _ = meterProvider.forceFlush()
      return metricExporter.metrics.value.last { $0.name == "http.client.request.duration" }
    }

    func durationPoints() -> [HistogramPointData] {
      durationMetric()?.data.points.compactMap { $0 as? HistogramPointData } ?? []
    }
  }

  final class InMemorySpanExporter: SpanExporter, @unchecked Sendable {
    let spans = LockIsolated<[SpanData]>([])

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
      self.spans.withValue { $0 += spans }
      return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) {}
  }

  final class InMemoryMetricExporter: MetricExporter, @unchecked Sendable {
    let metrics = LockIsolated<[MetricData]>([])

    func export(metrics: [MetricData]) -> ExportResult {
      self.metrics.withValue { $0 += metrics }
      return .success
    }

    func export(metrics: [MetricData]) async -> ExportResult {
      self.metrics.withValue { $0 += metrics }
      return .success
    }

    func flush() -> ExportResult { .success }
    func shutdown() -> ExportResult { .success }

    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
      .cumulative
    }
  }

  @Suite
  struct PostgrestInstrumentationTests {
    struct TransportFailure: Error {}

    private let recorder = TelemetryRecorder()
    private let requests = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    /// The global active span and the client span's `traceparent`, as each request saw them.
    private let contexts = LockIsolated<[(activeSpanID: String?, traceParent: String?)]>([])

    private func makeClient(
      status: HTTPTypes.HTTPResponse.Status = .ok,
      body: String = "[]",
      failure: (any Error)? = nil
    ) throws -> PostgrestClient {
      let requests = self.requests
      let contexts = self.contexts
      return try PostgrestClient(
        configuration: .init(
          url: URL(string: "https://project-ref.supabase.co/rest/v1")!,
          http: .init(
            transport: ClosureTransport { request, _ in
              requests.withValue { $0.append(request) }
              contexts.withValue {
                $0.append(
                  (
                    OpenTelemetry.instance.contextProvider.activeSpan?.context.spanId.hexString,
                    ClientSpanContext.traceParent
                  ))
              }
              if let failure { throw failure }
              return (
                HTTPTypes.HTTPResponse(
                  status: status, headerFields: [.contentType: "application/json"]),
                HTTPBody(Data(body.utf8))
              )
            }
          ),
          retryEnabled: false
        )
      )
    }

    @Test
    func aSelectEmitsOneClientSpanWithTheSupabaseAttributes() async throws {
      let client = try makeClient()

      try await recorder.run {
        _ = try await client.from("users")
          .select("id,email")
          .eq("email", value: "john@doe.com")
          .order("created_at", ascending: false)
          .limit(10)
          .execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.name == "GET /rest/v1/users")
      #expect(span.kind == .client)
      #expect(span.instrumentationScope.name == "supabase.postgrest")
      #expect(span.status == .unset)
      #expect(
        span.attributes == [
          "http.request.method": .string("GET"),
          "url.full": .string(
            "https://project-ref.supabase.co/rest/v1/users?select=id%2Cemail&email=REDACTED&order=created_at.desc&limit=10"
          ),
          "server.address": .string("project-ref.supabase.co"),
          "server.port": .int(443),
          "http.response.status_code": .int(200),
          "supabase.postgrest.operation": .string("select"),
          "supabase.postgrest.table": .string("users"),
        ])
    }

    @Test
    func anRPCCallRecordsTheFunctionAndNoTable() async throws {
      let client = try makeClient()

      try await recorder.run {
        _ = try await client.rpc("get_scores", params: ["min": 10]).execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.name == "POST /rest/v1/rpc/get_scores")
      #expect(span.attributes["supabase.postgrest.operation"] == .string("rpc"))
      #expect(span.attributes["supabase.postgrest.function"] == .string("get_scores"))
      #expect(span.attributes["supabase.postgrest.table"] == nil)
    }

    @Test
    func aGetRPCCallRedactsEveryQueryValue() async throws {
      let client = try makeClient()

      try await recorder.run {
        _ = try await client.rpc("get_scores", params: ["min": 10], get: true)
          .select("id")
          .limit(1)
          .execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(
        span.attributes["url.full"]
          == .string(
            "https://project-ref.supabase.co/rest/v1/rpc/get_scores?min=REDACTED&select=REDACTED&limit=REDACTED"
          ))
    }

    @Test
    func theSpanIsTheChildOfTheActiveSpan() async throws {
      let client = try makeClient()

      let parent = try await recorder.run {
        try await recorder.inParentSpan {
          _ = try await client.from("users").select().execute()
        }
      }

      let span = try #require(recorder.spans.first { $0.name == "GET /rest/v1/users" })
      #expect(span.traceId == parent.traceId)
      #expect(span.parentSpanId == parent.spanId)
    }

    /// On Apple platforms the default context manager ties the active span to a thread, which an
    /// `await` can leave, so the span reaches `traceparent` through a task-local instead.
    @Test
    func theSpanReachesTraceparentWithoutBecomingTheActiveSpan() async throws {
      let client = try makeClient()

      try await recorder.run {
        _ = try await client.from("users").select().execute()
      }

      let span = try #require(recorder.spans.only)
      let context = try #require(contexts.value.only)
      #expect(context.activeSpanID == nil)
      #expect(context.traceParent == "00-\(span.traceId.hexString)-\(span.spanId.hexString)-01")
    }

    @Test
    func anErrorStatusMarksTheSpanAsFailed() async throws {
      let client = try makeClient(
        status: .notFound, body: #"{"code":"PGRST205","message":"no table"}"#)

      await recorder.run {
        _ = try? await client.from("missing").select().execute()
      }

      let span = try #require(recorder.spans.only)
      #expect(span.status == .error(description: "404"))
      #expect(span.attributes["http.response.status_code"] == .int(404))
      #expect(span.attributes["error.type"] == .string("404"))
    }

    @Test
    func aTransportFailureRecordsTheErrorTypeAndNoStatusCode() async throws {
      let client = try makeClient(failure: URLError(.notConnectedToInternet))

      await recorder.run {
        _ = try? await client.from("users").select().execute()
      }

      let span = try #require(recorder.spans.only)
      let urlError = String(reflecting: URLError.self)
      #expect(span.status == .error(description: urlError))
      #expect(span.attributes["error.type"] == .string(urlError))
      #expect(span.attributes["http.response.status_code"] == nil)
    }

    @Test
    func aCallRejectedBeforeSendingEmitsNothing() async throws {
      let client = try makeClient()

      await recorder.run {
        _ = try? await client.from("users").select().csv().stripNulls().execute()
      }

      #expect(requests.value.isEmpty)
      #expect(recorder.spans.isEmpty)
      #expect(recorder.durationPoints().isEmpty)
    }

    @Test
    func eachCallRecordsOneDurationInSecondsWithoutTheURL() async throws {
      let client = try makeClient(status: .created)

      try await recorder.run {
        _ = try await client.from("users").insert(["email": "john@doe.com"]).execute()
      }

      let metric = try #require(recorder.durationMetric())
      #expect(metric.unit == "s")
      #expect(metric.instrumentationScopeInfo.name == "supabase.postgrest")
      let point = try #require(
        metric.data.points.compactMap { $0 as? HistogramPointData }.only)
      #expect(point.count == 1)
      #expect(point.boundaries.first == 0.005)
      #expect(point.boundaries.last == 10)
      #expect(
        point.attributes == [
          "http.request.method": .string("POST"),
          "server.address": .string("project-ref.supabase.co"),
          "server.port": .int(443),
          "url.scheme": .string("https"),
          "http.response.status_code": .int(201),
          "supabase.postgrest.operation": .string("insert"),
          "supabase.postgrest.table": .string("users"),
        ])
    }
  }

  extension Collection {
    /// The only element, or `nil` when there are none or more than one.
    fileprivate var only: Element? { count == 1 ? first : nil }
  }
#endif
