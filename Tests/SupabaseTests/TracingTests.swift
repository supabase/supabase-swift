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
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeMockSession()))
        )
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
            autoRefresh: .manual
          ),
          global: SupabaseClientOptions.GlobalOptions(
            http: .init(transport: URLSessionTransport(session: makeMockSession()))
          )
        )
      )

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
