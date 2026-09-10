//
//  HTTPClientConfiguration.swift
//  Helpers
//
//  Created by Guilherme Souza on 10/09/26.
//

/// The transport and middleware chain a client sends through.
///
/// Pass one of these as `http:` to any sub-client or to
/// `SupabaseClientOptions.GlobalOptions`. ``transport`` is `nil` by default, which means the
/// default ``URLSessionTransport`` (`URLSession.shared`, or `GlobalOptions.session` when used
/// through `SupabaseClient`).
/// Middlewares run in array order for requests (index 0 first) and in reverse for responses,
/// before the SDK's own middlewares and the transport.
public struct HTTPClientConfiguration: Sendable {
  /// The transport, or `nil` for the default ``URLSessionTransport``.
  public var transport: (any ClientTransport)?

  /// Middlewares run before the SDK's own, in order.
  public var middlewares: [any ClientMiddleware]

  /// Creates a configuration.
  ///
  /// - Parameters:
  ///   - transport: The transport, or `nil` for the default ``URLSessionTransport``.
  ///   - middlewares: Middlewares run before the SDK's own, in order.
  public init(
    transport: (any ClientTransport)? = nil,
    middlewares: [any ClientMiddleware] = []
  ) {
    self.transport = transport
    self.middlewares = middlewares
  }
}

extension HTTPClient {
  /// Builds the client for `configuration`, appending the module's own middlewares after the caller's.
  package init(
    configuration: HTTPClientConfiguration,
    appending moduleMiddlewares: [any ClientMiddleware]
  ) {
    self.init(
      transport: configuration.transport ?? URLSessionTransport(),
      middlewares: configuration.middlewares + moduleMiddlewares)
  }
}
