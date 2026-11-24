import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Supabase

#if OpenTelemetry
  import ConcurrencyExtras
  import OpenTelemetryApi
  import OpenTelemetrySdk
  @testable import PostgREST
#endif

@Suite(.serialized)
struct TracingTests {
  private let transport = RecordingTransport { _, _ in
    (HTTPResponse(status: .ok), Data("[]".utf8))
  }

  private func makeClient() throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(http: .init(transport: transport))
      )
    )
  }

  @Test
  func noActiveSpanProducesNilHeader() {
    #expect(TraceContext.traceParentHeader() == nil)
  }

  @Test
  func tracePropagationIsNoOpWithoutActiveSpan() async throws {
    let client = try makeClient()

    _ = try? await client.from("todos").select().execute()

    let request = try #require(transport.requests.first)
    #expect(request.head.headerFields[HTTPField.Name("traceparent")!] == nil)
  }

  #if OpenTelemetry
    @Test
    func tracePropagationInjectsTraceParentHeaderIntoRestRequests() async throws {
      let tracer = TracerProviderBuilder().build().get(instrumentationName: "test")
      let span = tracer.spanBuilder(spanName: "test-span").startSpan()
      defer { span.end() }

      let client = try makeClient()

      try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
        _ = try? await client.from("todos").select().execute()
      }

      let context = span.context
      let expected =
        "00-\(context.traceId.hexString)-\(context.spanId.hexString)-\(context.traceFlags.hexString)"
      let request = try #require(transport.requests.first)
      #expect(request.head.headerFields[HTTPField.Name("traceparent")!] == expected)
    }

    @Test
    func traceParentNamesThePostgrestSpanWhenTheTracerRecords() async throws {
      let recorder = TraceRecorder()
      let client = try makeClient()

      let parent = try await PostgrestInstrumentation.$providers.withValue(
        .init(tracerProvider: recorder.tracerProvider, meterProvider: DefaultMeterProvider.instance)
      ) {
        try await recorder.inSpan {
          _ = try await client.from("todos").select().execute()
        }
      }

      let span = try #require(recorder.spans.first { $0.name == "GET /rest/v1/todos" })
      #expect(span.parentSpanId == parent.spanId)
      let request = try #require(transport.requests.first)
      #expect(
        request.head.headerFields[HTTPField.Name("traceparent")!]
          == "00-\(span.traceId.hexString)-\(span.spanId.hexString)-01")
    }
  #endif
}

#if OpenTelemetry
  /// A tracer that records, with the spans it ended.
  final class TraceRecorder: SpanExporter, @unchecked Sendable {
    private let exported = LockIsolated<[SpanData]>([])
    private(set) var tracerProvider: TracerProviderSdk!

    init() {
      tracerProvider = TracerProviderBuilder()
        .add(spanProcessor: SimpleSpanProcessor(spanExporter: self))
        .build()
    }

    /// The ended spans. The span processor exports on a queue, so this flushes it first.
    var spans: [SpanData] {
      tracerProvider.forceFlush()
      return exported.value
    }

    /// Runs `work` with an app span active and returns its context. `@concurrent` because
    /// `withActiveSpan` is.
    @concurrent
    func inSpan(_ work: @Sendable () async throws -> Void) async throws -> SpanContext {
      let span = tracerProvider.get(instrumentationName: "app").spanBuilder(spanName: "screen")
        .startSpan()
      defer { span.end() }
      try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) { try await work() }
      return span.context
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
      exported.withValue { $0 += spans }
      return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) {}
  }
#endif
