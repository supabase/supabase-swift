//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthClient {
  /// Configuration struct represents the client configuration.
  ///
  /// This struct contains all the configuration options for the AuthClient including
  /// storage settings, authentication flow type, and custom headers.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let configuration = AuthClient.Configuration(
  ///   headers: ["X-Custom-Header": "value"],
  ///   flowType: .pkce,
  ///   redirectToURL: URL(string: "myapp://auth/callback"),
  ///   storageKey: "myapp_auth",
  ///   localStorage: KeychainLocalStorage(),
  ///   logger: MyCustomLogger(),
  ///   autoRefreshToken: true
  /// )
  ///
  /// let authClient = AuthClient(
  ///   url: URL(string: "https://myproject.supabase.co/auth/v1")!,
  ///   configuration: configuration
  /// )
  /// ```
  public struct Configuration: Sendable {
    /// Any additional headers to send to the Auth server.
    /// These headers will be included in all authentication requests.
    public var headers: [String: String]
    
    /// The authentication flow type to use.
    /// - `.implicit`: Uses implicit flow (less secure, not recommended)
    /// - `.pkce`: Uses PKCE flow (recommended for mobile apps)
    public let flowType: AuthFlowType

    /// Default URL to be used for redirect on the flows that requires it.
    /// This is used for OAuth flows and password reset emails.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    /// If not provided, a default key will be used.
    public var storageKey: String?

    /// Provider your own local storage implementation to use instead of the default one.
    /// Common implementations include `KeychainLocalStorage` for secure storage
    /// and `InMemoryLocalStorage` for testing.
    public let localStorage: any AuthLocalStorage

    /// Custom SupabaseLogger implementation used to inspecting log messages from the Auth library.
    /// Useful for debugging authentication issues.
    public let logger: SupabaseLogger?
    
    /// The JSON encoder to use for encoding requests.
    public let encoder: JSONEncoder
    
    /// The JSON decoder to use for decoding responses.
    public let decoder: JSONDecoder

    /// The Alamofire session to use for network requests.
    /// Allows customization of network behavior, timeouts, and interceptors.
    public let session: Alamofire.Session

    /// Set to `true` if you want to automatically refresh the token before expiring.
    /// When enabled, the client will automatically refresh tokens in the background.
    public let autoRefreshToken: Bool

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
    ///   - storageKey: Optional key name used for storing tokens in local storage.
    ///   - localStorage: The storage mechanism for local data.
    ///   - logger: The logger to use.
    ///   - encoder: The JSON encoder to use for encoding requests.
    ///   - decoder: The JSON decoder to use for decoding responses.
    ///   - session: The Alamofire session to use for network requests.
    ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
    public init(
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: SupabaseLogger? = nil,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      session: Alamofire.Session = .default,
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      self.logger = logger
      self.encoder = encoder
      self.decoder = decoder
      self.session = session
      self.autoRefreshToken = autoRefreshToken
    }
  }

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type..
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data..
  ///   - logger: The logger to use.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - session: The Alamofire session to use for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  public init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: SupabaseLogger? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    session: Alamofire.Session = .default,
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
  ) {
    self.init(
      url: url,
      configuration: Configuration(
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        encoder: encoder,
        decoder: decoder,
        session: session,
        autoRefreshToken: autoRefreshToken
      )
    )
  }
}
