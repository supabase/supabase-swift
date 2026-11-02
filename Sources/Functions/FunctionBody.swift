public import Foundation
import Helpers

/// A request body together with its `Content-Type`.
///
/// Pass it to ``FunctionsClient/invoke(_:body:options:)``. The factory methods set the content
/// type for you.
///
/// ```swift
/// try await functions.invoke("send-email", body: .json(["to": "user@example.com"]))
/// try await functions.invoke("echo", body: .text("hello"))
/// ```
///
/// > Note: v3 also offers `FunctionBody.stream(_:contentType:)` for streamed uploads. v2 buffers
/// > the body in memory, so it has no equivalent.
public struct FunctionBody: Sendable {
  /// The `Content-Type` header value sent with the body.
  public let contentType: String

  /// The bytes sent as the request body.
  public let data: Data

  /// Encodes `value` as JSON with `Content-Type: application/json`.
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - encoder: The encoder to use. Defaults to the SDK's standard JSON encoder when `nil`.
  /// - Throws: The `EncodingError` the encoder throws.
  public static func json(
    _ value: some Encodable,
    encoder: JSONEncoder? = nil
  ) throws -> FunctionBody {
    FunctionBody(contentType: "application/json", data: try (encoder ?? .supabase()).encode(value))
  }

  /// Sends `string` as UTF-8 with `Content-Type: text/plain; charset=utf-8`.
  public static func text(_ string: String) -> FunctionBody {
    FunctionBody(contentType: "text/plain; charset=utf-8", data: Data(string.utf8))
  }

  /// Sends raw bytes.
  /// - Parameters:
  ///   - data: The bytes to send.
  ///   - contentType: The `Content-Type` header value. Defaults to `application/octet-stream`.
  public static func data(
    _ data: Data,
    contentType: String = "application/octet-stream"
  ) -> FunctionBody {
    FunctionBody(contentType: contentType, data: data)
  }
}
