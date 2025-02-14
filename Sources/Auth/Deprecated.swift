//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import Foundation
import Helpers

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
    message: "Access to the default JSONEncoder instance moved to AuthClient.Configuration.jsonEncoder"
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
    message: "Access to the default JSONDecoder instance moved to AuthClient.Configuration.jsonDecoder"
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
    message: "Replace usages of this initializer with new init(url:headers:flowType:localStorage:logger:encoder:decoder:fetch)"
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
    message: "Replace usages of this initializer with new init(url:headers:flowType:localStorage:logger:encoder:decoder:fetch)"
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

@available(*, deprecated, message: "Use MFATotpEnrollParams or MFAPhoneEnrollParams instead.")
public typealias MFAEnrollParams = MFATotpEnrollParams
