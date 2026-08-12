//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

public import Foundation

#if canImport(FoundationNetworking)
  public import FoundationNetworking
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
      "Replace usages of this initializer with new init(url:headers:flowType:localStorage:logger:encoder:decoder:fetch)"
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
      localStorage: localStorage,
      logger: nil,
      encoder: encoder,
      decoder: decoder,
      fetch: fetch
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
      "Replace usages of this initializer with new init(url:headers:flowType:localStorage:logger:encoder:decoder:fetch)"
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
      url: url,
      headers: headers,
      flowType: flowType,
      localStorage: localStorage,
      logger: nil,
      encoder: encoder,
      decoder: decoder,
      fetch: fetch
    )
  }
}

extension AuthClient.Configuration {
  /// Initializes a AuthClient Configuration with a custom JSON encoder/decoder.
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
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON encoding/decoding is no longer supported. Remove the encoder/decoder arguments; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder,
    decoder: JSONDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
  ) {
    self.init(
      url: url,
      headers: headers,
      flowType: flowType,
      redirectToURL: redirectToURL,
      storageKey: storageKey,
      localStorage: localStorage,
      logger: logger,
      resolvedEncoder: encoder,
      resolvedDecoder: decoder,
      fetch: fetch,
      autoRefreshToken: autoRefreshToken,
      emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
    )
  }

  /// Initializes a AuthClient Configuration with a custom JSON encoder.
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
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON encoding is no longer supported. Remove the encoder argument; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
  ) {
    self.init(
      url: url,
      headers: headers,
      flowType: flowType,
      redirectToURL: redirectToURL,
      storageKey: storageKey,
      localStorage: localStorage,
      logger: logger,
      resolvedEncoder: encoder,
      resolvedDecoder: AuthClient.Configuration.jsonDecoder,
      fetch: fetch,
      autoRefreshToken: autoRefreshToken,
      emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
    )
  }

  /// Initializes a AuthClient Configuration with a custom JSON decoder.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data.
  ///   - logger: The logger to use.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON decoding is no longer supported. Remove the decoder argument; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    decoder: JSONDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
  ) {
    self.init(
      url: url,
      headers: headers,
      flowType: flowType,
      redirectToURL: redirectToURL,
      storageKey: storageKey,
      localStorage: localStorage,
      logger: logger,
      resolvedEncoder: AuthClient.Configuration.jsonEncoder,
      resolvedDecoder: decoder,
      fetch: fetch,
      autoRefreshToken: autoRefreshToken,
      emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
    )
  }
}

extension AuthClient {
  /// Initializes a AuthClient with a custom JSON encoder/decoder.
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
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON encoding/decoding is no longer supported. Remove the encoder/decoder arguments; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder,
    decoder: JSONDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
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
        resolvedEncoder: encoder,
        resolvedDecoder: decoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
      )
    )
  }

  /// Initializes a AuthClient with a custom JSON encoder.
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
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON encoding is no longer supported. Remove the encoder argument; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
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
        resolvedEncoder: encoder,
        resolvedDecoder: AuthClient.Configuration.jsonDecoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
      )
    )
  }

  /// Initializes a AuthClient with a custom JSON decoder.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type.
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data.
  ///   - logger: The logger to use.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  @available(
    *,
    deprecated,
    message:
      "Customizing Auth's JSON decoding is no longer supported. Remove the decoder argument; this initializer will be removed in a future major version."
  )
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    decoder: JSONDecoder,
    fetch: @escaping AuthClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
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
        resolvedEncoder: AuthClient.Configuration.jsonEncoder,
        resolvedDecoder: decoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
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
