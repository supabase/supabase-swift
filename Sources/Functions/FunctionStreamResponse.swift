public import Foundation
public import HTTPTypes

/// The head of a streamed invocation, with the body still arriving.
///
/// ``FunctionsClient/stream(_:body:options:)`` returns it once the function answers with a 2xx
/// status. Iterate ``body`` to read the chunks.
///
/// ```swift
/// let response = try await functions.stream("chat", body: .json(prompt))
/// for try await chunk in response.body {
///   print(String(decoding: chunk, as: UTF8.self))
/// }
/// ```
///
/// > Note: In v3, ``body`` is an `HTTPBody` that yields byte slices. In v2 it yields `Data`.
public struct FunctionStreamResponse: Sendable, CustomStringConvertible {
  /// The HTTP status the function answered with.
  public var status: HTTPResponse.Status

  /// Every response header.
  public var headers: HTTPFields

  /// The response body, as chunks of `Data` in arrival order.
  public var body: AsyncThrowingStream<Data, any Error>

  /// The `Content-Type` header, when present.
  public var contentType: String? { headers[.contentType] }

  /// The edge region that served the call, from `x-sb-edge-region`.
  public var region: FunctionRegion? {
    headers[.xSbEdgeRegion].map(FunctionRegion.init(rawValue:))
  }

  /// The worker execution id, from `x-deno-execution-id`.
  public var executionID: String? { headers[.xDenoExecutionID] }

  /// The gateway request id, from `sb-request-id`.
  public var requestID: String? { headers[.sbRequestID] }

  public var description: String {
    "FunctionStreamResponse(status: \(status.code), contentType: \(contentType ?? "none"))"
  }
}
