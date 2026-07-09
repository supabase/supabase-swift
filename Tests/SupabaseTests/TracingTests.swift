import Foundation
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if OpenTelemetry
  import OpenTelemetryApi
  import OpenTelemetrySdk
#endif

/// `.serialized`: OpenTelemetry's default context manager tracks the active span as ambient
/// state (OS activity scope), not a per-`Task` value, so tests that set/read it would otherwise
/// race against each other under Swift Testing's default parallel execution.
@Suite(.serialized)
struct TracingTests {
  @Test
  func noActiveSpanProducesNilHeader() {
    #expect(TraceContext.traceParentHeader() == nil)
  }

  @Test
  func tracePropagationIsNoOpWithoutActiveSpan() async throws {
    RequestCapturingProtocol.capturedRequests = []
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeMockSession())
      )
    )

    _ = try? await client.from("todos").select().execute()

    let request = try #require(RequestCapturingProtocol.capturedRequests.first)
    #expect(request.value(forHTTPHeaderField: "traceparent") == nil)
  }

  #if OpenTelemetry
    @Test
    func tracePropagationInjectsTraceParentHeaderIntoRestRequests() async throws {
      let tracer = TracerProviderBuilder().build().get(instrumentationName: "test")
      let span = tracer.spanBuilder(spanName: "test-span").startSpan()
      defer { span.end() }

      RequestCapturingProtocol.capturedRequests = []
      let client = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        options: SupabaseClientOptions(
          auth: SupabaseClientOptions.AuthOptions(
            storage: AuthLocalStorageMock(),
            autoRefreshToken: false
          ),
          global: SupabaseClientOptions.GlobalOptions(session: makeMockSession())
        )
      )

      // `withActiveSpan` (not the imperative setActiveSpan/removeContextForSpan) is the only
      // API that works with every default ContextManager — on Linux (no os.activity),
      // TaskLocalContextManager's imperative set/remove are no-ops.
      try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
        _ = try? await client.from("todos").select().execute()
      }

      let context = span.context
      let expected =
        "00-\(context.traceId.hexString)-\(context.spanId.hexString)-\(context.traceFlags.hexString)"
      let request = try #require(RequestCapturingProtocol.capturedRequests.first)
      #expect(request.value(forHTTPHeaderField: "traceparent") == expected)
    }
  #endif
}
