import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Supabase

#if OpenTelemetry
  import OpenTelemetryApi
  import OpenTelemetrySdk
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
  #endif
}
