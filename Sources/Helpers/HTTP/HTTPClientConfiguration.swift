//
//  HTTPClientConfiguration.swift
//  Helpers
//
//  Created by Guilherme Souza on 10/09/26.
//

/// The transport, middleware chain and request timeout a client sends through.
///
/// Pass one of these as `http:` to any sub-client or to
/// `SupabaseClientOptions.GlobalOptions`. ``transport`` is `nil` by default, which means the
/// default ``URLSessionTransport`` over `URLSession.shared`.
/// Middlewares run in array order for requests (index 0 first) and in reverse for responses,
/// before the SDK's own middlewares and the transport.
///
/// ```swift
/// let options = SupabaseClientOptions(
///   global: .init(http: .init(timeout: .seconds(30)))
/// )
/// ```
public struct HTTPClientConfiguration: Sendable {
  /// The transport, or `nil` for the default ``URLSessionTransport``.
  public var transport: (any ClientTransport)?

  /// Middlewares run before the SDK's own, in order.
  public var middlewares: [any ClientMiddleware]

  /// The per-request timeout, or `nil` for the module's default: 60 seconds, or
  /// `FunctionsClient.requestIdleTimeout` (150 seconds) for Edge Functions.
  ///
  /// This is an idle timeout, like `URLRequest.timeoutInterval`: the request fails once no data
  /// has moved for this long, so a slow but steady transfer is not cut short. ``URLSessionTransport``
  /// sets it on every `URLRequest`, so it takes precedence over the session's
  /// `URLSessionConfiguration.timeoutIntervalForRequest`; a custom ``ClientTransport`` owns its
  /// own timeout policy. Individual calls can override it — `FunctionInvokeOptions.timeout` for
  /// Functions, `PostgrestRequestBuilder.timeout(_:)` for PostgREST.
  public var timeout: Duration?

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - transport: The transport, or `nil` for the default ``URLSessionTransport``.
  ///   - middlewares: Middlewares run before the SDK's own, in order.
  ///   - timeout: The per-request idle timeout, or `nil` for the module's default.
  public init(
    transport: (any ClientTransport)? = nil,
    middlewares: [any ClientMiddleware] = [],
    timeout: Duration? = nil
  ) {
    self.transport = transport
    self.middlewares = middlewares
    self.timeout = timeout
  }
}

extension HTTPClient {
  /// Builds the client for `configuration`, appending the module's own middlewares after the
  /// caller's. `defaultTimeout` applies when the configuration leaves
  /// ``HTTPClientConfiguration/timeout`` unset.
  package init(
    configuration: HTTPClientConfiguration,
    appending moduleMiddlewares: [any ClientMiddleware],
    defaultTimeout: Duration = HTTPClient.defaultTimeout
  ) {
    self.init(
      transport: configuration.transport ?? URLSessionTransport(),
      middlewares: configuration.middlewares + moduleMiddlewares,
      timeout: configuration.timeout ?? defaultTimeout)
  }
}
