//
//  FunctionStreamResponse.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import HTTPTypes
public import Helpers

/// The streamed answer to an invocation: the head now, the body as it arrives.
///
/// A non-2xx status never reaches this type; ``FunctionsClient/stream(_:body:options:)`` throws
/// ``FunctionsError`` instead. Iterate ``body`` once.
///
/// ```swift
/// let response = try await functions.stream("chat", body: .json(prompt))
/// for try await chunk in response.body {
///   parser.feed(chunk)
/// }
/// ```
public struct FunctionStreamResponse: Sendable, CustomStringConvertible {
  /// The HTTP status the function answered with.
  public var status: HTTPResponse.Status

  /// Every response header. Import `HTTPTypes` to spell header names.
  public var headers: HTTPFields

  /// The response body, delivered chunk by chunk. Empty when the function sent none. One pass
  /// only: a second iteration throws `HTTPBodyAlreadyConsumedError`.
  ///
  /// Iterating it throws ``FunctionsError`` with kind
  /// ``FunctionsError/Kind-swift.struct/transport`` when the connection fails, and
  /// `CancellationError` when the iterating task is cancelled, which also closes the connection.
  public var body: HTTPBody

  /// The `Content-Type` header, when present.
  public var contentType: String? { headers[.contentType] }

  /// The edge region that served the call, from `x-sb-edge-region`.
  public var region: FunctionRegion? {
    headers[.xSbEdgeRegion].map(FunctionRegion.init(rawValue:))
  }

  /// The worker execution id, from `x-deno-execution-id`. Quote it to Supabase support.
  public var executionID: String? { headers[.xDenoExecutionID] }

  /// The gateway request id, from `sb-request-id`.
  public var requestID: String? { headers[.sbRequestID] }

  /// The status and content type. Never the body, which cannot be read twice anyway.
  public var description: String {
    "FunctionStreamResponse(status: \(status.code), contentType: \(contentType ?? "none"))"
  }
}
