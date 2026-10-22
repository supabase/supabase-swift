//
//  FunctionBody.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import Foundation
public import Helpers

/// What an invocation sends.
///
/// Each factory fixes the `Content-Type`; a per-call
/// ``FunctionInvokeOptions/headers`` entry for `Content-Type` overrides it.
///
/// ```swift
/// try await functions.invoke("order", body: .json(order))
/// try await functions.invoke("echo", body: .text("hello"))
/// try await functions.invoke("thumbnail", body: .data(jpeg, contentType: "image/jpeg"))
/// try await functions.invoke("transcribe", body: .stream(try HTTPBody(fileURL: url), contentType: "audio/m4a"))
/// ```
public struct FunctionBody: Sendable {
  /// The `Content-Type` sent with the body.
  public let contentType: String

  /// The bytes sent.
  public let httpBody: HTTPBody

  /// JSON-encodes `value` now, in the caller's isolation.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - encoder: The encoder to use. Defaults to the SDK encoder, which writes `Date` as ISO 8601.
  /// - Throws: ``FunctionsError`` with kind ``FunctionsError/Kind-swift.struct/invalidRequest``
  ///   wrapping the `EncodingError`. Nothing is sent.
  public static func json(
    _ value: some Encodable,
    encoder: JSONEncoder = .supabase()
  ) throws -> FunctionBody {
    do {
      return FunctionBody(
        contentType: "application/json", httpBody: HTTPBody(try encoder.encode(value)))
    } catch {
      throw FunctionsError(
        kind: .invalidRequest,
        message: "Failed to encode the Edge Function request body as JSON.",
        underlyingError: error
      )
    }
  }

  /// Sends `string` as `text/plain; charset=utf-8`.
  public static func text(_ string: String) -> FunctionBody {
    FunctionBody(contentType: "text/plain; charset=utf-8", httpBody: HTTPBody(Data(string.utf8)))
  }

  /// Sends raw bytes. Defaults to `application/octet-stream`.
  public static func data(
    _ data: Data,
    contentType: String = "application/octet-stream"
  ) -> FunctionBody {
    FunctionBody(contentType: contentType, httpBody: HTTPBody(data))
  }

  /// Sends a streamed body, such as `HTTPBody(fileURL:)` for a large upload.
  ///
  /// A body whose `iterationBehavior` is `.single` can be read once, so it cannot be retried
  /// or replayed after a redirect.
  public static func stream(_ body: HTTPBody, contentType: String) -> FunctionBody {
    FunctionBody(contentType: contentType, httpBody: body)
  }
}
