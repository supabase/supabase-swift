//
//  ClientSpanContext.swift
//  Helpers
//
//  Created by Guilherme Souza on 24/11/26.
//

/// The client span a module records for the request in flight, as the trace propagation sends it.
///
/// A module that records a client span sets ``traceParent`` while it sends the request, and the
/// `traceparent` header then names that span as the parent of the server's spans. It is a
/// task-local, not the OpenTelemetry active span: on Apple platforms the default OpenTelemetry
/// context manager ties the active span to a thread, and an `await` can resume on another one.
package enum ClientSpanContext {
  /// The W3C `traceparent` value of the client span, or `nil` outside one.
  @TaskLocal package static var traceParent: String?
}
