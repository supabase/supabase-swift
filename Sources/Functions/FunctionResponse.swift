public import Foundation
public import HTTPTypes

/// The buffered answer to an invocation: the status, every header and the body.
///
/// A non-2xx status never reaches this type; ``FunctionsClient/invoke(_:body:options:)`` throws
/// ``FunctionsError`` instead.
///
/// ```swift
/// let response = try await functions.invoke("report")
/// print(response.status, response.contentType ?? "", response.region?.rawValue ?? "")
/// let report = try response.decode(as: Report.self)
/// ```
public struct FunctionResponse: Sendable, CustomStringConvertible {
  /// The HTTP status the function answered with.
  public var status: HTTPResponse.Status

  /// Every response header.
  public var headers: HTTPFields

  /// The raw response body. Empty when the function sent none.
  public var body: Data

  let decoder: JSONDecoder

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

  /// ``body`` as UTF-8, or `nil` when it is not valid UTF-8.
  public var text: String? { String(data: body, encoding: .utf8) }

  /// JSON-decodes ``body``.
  ///
  /// - Parameters:
  ///   - type: The type to decode. Inferred from the call site when omitted.
  ///   - decoder: Overrides the client's ``FunctionsClient/decoder`` for this call.
  /// - Throws: The `DecodingError` the decoder throws.
  public func decode<T: Decodable>(as type: T.Type = T.self, decoder: JSONDecoder? = nil) throws
    -> T
  {
    try (decoder ?? self.decoder).decode(T.self, from: body)
  }

  public var description: String {
    "FunctionResponse(status: \(status.code), contentType: \(contentType ?? "none"), bytes: \(body.count))"
  }
}
