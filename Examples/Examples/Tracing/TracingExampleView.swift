//
//  TracingExampleView.swift
//  Examples
//
//  Demonstrates W3C trace context propagation with Supabase and OpenTelemetry.
//

import OpenTelemetryApi
import OpenTelemetrySdk
import Supabase
import SwiftUI

// A SupabaseClient configured with trace propagation via OTelTraceContextProvider.
// In your app, configure tracePropagation once when initializing your shared client.
private let tracingClient: SupabaseClient = {
  let url = URL(string: SupabaseConfig["SUPABASE_URL"] ?? "https://example.supabase.co")!
  let key =
    SupabaseConfig["SUPABASE_PUBLISHABLE_KEY"] ?? SupabaseConfig["SUPABASE_ANON_KEY"] ?? ""
  return SupabaseClient(
    supabaseURL: url,
    supabaseKey: key,
    options: .init(
      global: .init(tracePropagation: OTelTraceContextProvider())
    )
  )
}()

struct TracingExampleView: View {
  @State private var traceparent = ""
  @State private var status = ""
  @State private var isRunning = false

  var body: some View {
    List {
      Section {
        Text(
          "Each outgoing Supabase request is tagged with the active OpenTelemetry span via the W3C traceparent header."
        )
        .font(.subheadline)
        .foregroundColor(.secondary)
      }

      Section("Client Setup") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Initialize SupabaseClient with:")
            .font(.caption)
            .foregroundColor(.secondary)
          Text(
            """
            SupabaseClient(
              supabaseURL: url,
              supabaseKey: key,
              options: .init(
                global: .init(
                  tracePropagation:
                    OTelTraceContextProvider()
                )
              )
            )
            """
          )
          .font(.caption.monospaced())
          .padding(8)
          .background(Color(.secondarySystemBackground))
          .cornerRadius(6)
        }
        .padding(.vertical, 4)
      }

      Section("Live Demo") {
        Button {
          runDemo()
        } label: {
          HStack {
            Label(
              "Start span & query Supabase",
              systemImage: "antenna.radiowaves.left.and.right"
            )
            Spacer()
            if isRunning {
              ProgressView()
            }
          }
        }
        .disabled(isRunning)

        if !traceparent.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Injected traceparent:")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(traceparent)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
          .padding(.vertical, 4)
        }

        if !status.isEmpty {
          Text(status)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Tracing")
  }

  @MainActor
  private func runDemo() {
    isRunning = true
    traceparent = ""
    status = ""

    Task { @MainActor in
      let provider = TracerProviderSdk()
      OpenTelemetry.registerTracerProvider(tracerProvider: provider)
      let tracer = OpenTelemetry.instance.tracerProvider.get(
        instrumentationName: "supabase-swift-examples",
        instrumentationVersion: nil
      )

      let span = tracer.spanBuilder(spanName: "supabase.query").startSpan()
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)
      defer {
        span.end()
        OpenTelemetry.instance.contextProvider.removeContextForSpan(span)
      }

      let ctx = span.context
      let flags = String(format: "%02x", ctx.traceFlags.rawValue)
      traceparent = "00-\(ctx.traceId.hexString)-\(ctx.spanId.hexString)-\(flags)"

      do {
        _ = try await tracingClient.from("todos").select().execute()
        status =
          "Request completed. Check your tracing backend for trace ID: \(ctx.traceId.hexString)"
      } catch {
        // The request was sent with the traceparent header even if it failed.
        status =
          "Request sent with traceparent header. (Error: \(error.localizedDescription))"
      }

      isRunning = false
    }
  }
}
