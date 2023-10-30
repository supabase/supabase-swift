import Foundation

struct NoParams: Encodable {}

public final class PostgrestRpcBuilder: PostgrestBuilder {
  /// Performs a function call with parameters.
  /// - Parameters:
  ///   - params: The parameters to pass to the function.
  ///   - head: When set to `true`, the function call will use the `HEAD` method. Default is
  /// `false`.
  ///   - count: Count algorithm to use to count rows in a table. Default is `nil`.
  /// - Returns: The `PostgrestTransformBuilder` instance for method chaining.
  /// - Throws: An error if the function call fails.
  func rpc(
    params: some Encodable,
    head: Bool = false,
    count: CountOption? = nil
  ) throws -> PostgrestTransformBuilder {
    // TODO: Support `HEAD` method
    // https://github.com/supabase/postgrest-js/blob/master/src/lib/PostgrestRpcBuilder.ts#L38
    assert(head == false, "HEAD is not currently supported yet.")

    method = "POST"
    if params is NoParams {
      // noop
    } else {
      body = try configuration.encoder.encode(params)
    }

    if let count {
      if let prefer = headers["Prefer"] {
        headers["Prefer"] = "\(prefer),count=\(count.rawValue)"
      } else {
        headers["Prefer"] = "count=\(count.rawValue)"
      }
    }

    return PostgrestTransformBuilder(self)
  }
}
