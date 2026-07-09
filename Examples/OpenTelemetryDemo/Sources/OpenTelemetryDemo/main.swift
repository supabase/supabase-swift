import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import StdoutExporter
import Supabase

// Prints every request handed to it — proves the traceparent header the SDK attaches while a
// span is active, without needing a real Supabase project or network access.
final class RequestPrintingProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    print("→ \(request.httpMethod ?? "GET") \(request.url!.absoluteString)")
    print("  traceparent: \(request.value(forHTTPHeaderField: "traceparent") ?? "<none>")\n")

    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

struct NoOpAuthLocalStorage: AuthLocalStorage {
  func store(key: String, value: Data) throws {}
  func retrieve(key: String) throws -> Data? { nil }
  func remove(key: String) throws {}
}

// 1. Set up an OTel tracer that prints every span it exports to stdout.
let tracerProvider = TracerProviderBuilder()
  .add(spanProcessor: SimpleSpanProcessor(spanExporter: StdoutSpanExporter(isDebug: true)))
  .build()
OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
let tracer = tracerProvider.get(instrumentationName: "OpenTelemetryDemo")

// 2. Point SupabaseClient at the request-printing stub above — no live project needed to see
//    the traceparent header the SDK attaches.
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [RequestPrintingProtocol.self]

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://example.supabase.co")!,
  supabaseKey: "demo-anon-key",
  options: SupabaseClientOptions(
    auth: .init(storage: NoOpAuthLocalStorage(), autoRefreshToken: false),
    global: .init(session: URLSession(configuration: config))
  )
)

// 3. Make a request while a span is active. Enabling the `OpenTelemetry` trait (see
//    Package.swift) is the only thing that makes SupabaseClient attach the traceparent header —
//    no extra configuration on the client itself.
let span = tracer.spanBuilder(spanName: "list-todos").startSpan()
await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
  _ = try? await supabase.from("todos").select().execute()
}

print("Compare the traceId/spanId above with the exported span below.\n")
span.end()
