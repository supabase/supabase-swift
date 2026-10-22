//
//  FunctionResponse.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import Foundation
public import HTTPTypes
public import Helpers

/// The buffered answer to an invocation: the status, every header and the body.
///
/// A non-2xx status never reaches this type; ``FunctionsClient/invoke(_:body:options:)`` throws
/// ``FunctionsError`` instead.
///
/// ```swift
/// let response = try await functions.invoke("report")
/// print(response.status, response.contentType ?? "", response.region ?? "")
/// let report = try response.decode(as: Report.self)
/// ```
public struct FunctionResponse: Sendable, CustomStringConvertible {
  /// The HTTP status the function answered with.
  public var status: HTTPResponse.Status

  /// Every response header. Import `HTTPTypes` to spell header names.
  public var headers: HTTPFields

  /// The raw response body. Empty when the function sent none.
  public var body: Data

  /// The decoder ``decode(as:decoder:)`` uses when the call passes none.
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
  ///   - decoder: Overrides the client's ``FunctionsClient/Configuration/decoder`` for this call.
  /// - Throws: ``FunctionsError`` with kind ``FunctionsError/Kind-swift.struct/decoding``
  ///   wrapping the `DecodingError`.
  public func decode<T: Decodable>(as type: T.Type = T.self, decoder: JSONDecoder? = nil) throws
    -> T
  {
    do {
      return try (decoder ?? self.decoder).decode(T.self, from: body)
    } catch {
      throw FunctionsError(
        kind: .decoding,
        message: "Failed to decode the Edge Function response as \(T.self).",
        underlyingError: error
      )
    }
  }

  /// The status, content type and byte count. Never the body, so a stray `print` cannot leak
  /// a payload into a log.
  public var description: String {
    "FunctionResponse(status: \(status.code), contentType: \(contentType ?? "none"), bytes: \(body.count))"
  }
}
