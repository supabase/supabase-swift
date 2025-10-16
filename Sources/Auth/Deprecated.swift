//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@available(*, deprecated, renamed: "AuthClient")
public typealias GoTrueClient = AuthClient

@available(*, deprecated, renamed: "AuthMFA")
public typealias GoTrueMFA = AuthMFA

@available(*, deprecated, renamed: "AuthLocalStorage")
public typealias GoTrueLocalStorage = AuthLocalStorage

@available(*, deprecated, renamed: "AuthMetaSecurity")
public typealias GoTrueMetaSecurity = AuthMetaSecurity

@available(*, deprecated, renamed: "AuthError")
public typealias GoTrueError = AuthError

extension JSONEncoder {
  @available(
    *,
    deprecated,
    renamed: "AuthClient.Configuration.jsonEncoder",
    message:
      "Access to the default JSONEncoder instance moved to AuthClient.Configuration.jsonEncoder"
  )
  public static var goTrue: JSONEncoder {
    AuthClient.Configuration.jsonEncoder
  }
}

extension JSONDecoder {
  @available(
    *,
    deprecated,
    renamed: "AuthClient.Configuration.jsonDecoder",
    message:
      "Access to the default JSONDecoder instance moved to AuthClient.Configuration.jsonDecoder"
  )
  public static var goTrue: JSONDecoder {
    AuthClient.Configuration.jsonDecoder
  }
}

extension AuthClient.Configuration {
  /// Initializes a AuthClient Configuration with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - localStorage: The storage mechanism for local data.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  @available(
    *,
    deprecated,
    message:
      "Replace usages of this initializer with new init(url:headers:flowType:redirectToURL:storageKey:localStorage:logger:encoder:decoder:alamofireSession:autoRefreshToken:)"
  )
  public init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Self.defaultFlowType,
    localStorage: any AuthLocalStorage,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.init(
      url: url,
      headers: headers,
      flowType: flowType,
      redirectToURL: nil,
      storageKey: nil,
      localStorage: localStorage,
      logger: nil,
      encoder: encoder,
      decoder: decoder,
      fetch: fetch,
      alamofireSession: .default,
      autoRefreshToken: Self.defaultAutoRefreshToken
    )
  }

  /// Initializes a AuthClient Configuration with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data.
  ///   - logger: The logger to use.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  @available(
    *,
    deprecated,
    message:
      "Use init(url:headers:flowType:redirectToURL:storageKey:localStorage:logger:encoder:decoder:alamofireSession:autoRefreshToken:) instead. This initializer will be removed in a future version."
  )
  @_disfavoredOverload
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Self.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    fetch: @escaping AuthClient.FetchHandler,
    autoRefreshToken: Bool = Self.defaultAutoRefreshToken
  ) {
    self.init(
      url: url,
      headers: headers,
      flowType: flowType,
      redirectToURL: redirectToURL,
      storageKey: storageKey,
      localStorage: localStorage,
      logger: logger,
      encoder: encoder,
      decoder: decoder,
      fetch: fetch,
      alamofireSession: .default,
      autoRefreshToken: autoRefreshToken
    )
  }
}

extension AuthClient {
  /// Initializes a AuthClient Configuration with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - localStorage: The storage mechanism for local data.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  @available(
    *,
    deprecated,
    message:
      "Replace usages of this initializer with new init(url:headers:flowType:redirectToURL:storageKey:localStorage:logger:encoder:decoder:alamofireSession:autoRefreshToken:)"
  )
  public init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Configuration.defaultFlowType,
    localStorage: any AuthLocalStorage,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        localStorage: localStorage,
        encoder: encoder,
        decoder: decoder,
        fetch: fetch
      )
    )
  }

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data.
  ///   - logger: The logger to use.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  @available(
    *,
    deprecated,
    message:
      "Use init(url:headers:flowType:redirectToURL:storageKey:localStorage:logger:encoder:decoder:alamofireSession:autoRefreshToken:) instead. This initializer will be removed in a future version."
  )
  @_disfavoredOverload
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    fetch: @escaping AuthClient.FetchHandler,
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        encoder: encoder,
        decoder: decoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken
      )
    )
  }
}

@available(*, deprecated, message: "Use MFATotpEnrollParams or MFAPhoneEnrollParams instead.")
public typealias MFAEnrollParams = MFATotpEnrollParams

extension AuthAdmin {
  @available(
    *,
    deprecated,
    message: "Use deleteUser with UUID instead of string."
  )
  public func deleteUser(id: String, shouldSoftDelete: Bool = false) async throws {
    guard let id = UUID(uuidString: id) else {
      fatalError("id should be a valid UUID")
    }

    try await self.deleteUser(id: id, shouldSoftDelete: shouldSoftDelete)
  }
}
