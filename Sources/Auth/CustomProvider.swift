//
//  CustomProvider.swift
//  Auth
//
//  Created by Guilherme Souza on 03/11/26.
//

public import Foundation
public import Helpers

/// The protocol a custom provider speaks.
public struct CustomProviderType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A plain OAuth 2.0 provider. You give its authorization, token, and userinfo URLs.
  public static let oauth2: CustomProviderType = "oauth2"

  /// An OpenID Connect provider. The server reads its endpoints from the discovery document.
  public static let oidc: CustomProviderType = "oidc"
}

/// A custom OAuth 2.0 or OIDC provider registered in Supabase Auth.
///
/// Users sign in with it through ``AuthClient/oauthSignInURL(_:options:)``, passing
/// ``identifier`` as the provider.
public struct CustomProvider: Decodable, Hashable, Sendable, Identifiable {
  /// The provider's unique ID.
  public let id: UUID

  /// Whether the provider uses OAuth 2.0 or OIDC.
  public let providerType: CustomProviderType

  /// The name used to sign in with the provider. It starts with `custom:`, such as
  /// `custom:acme`.
  public let identifier: String

  /// The name shown to people.
  public let name: String

  /// The OAuth client ID.
  public let clientID: String

  /// More client IDs that the server accepts when it checks an ID token.
  public let acceptableClientIDs: [String]

  /// The scopes the server requests at the provider.
  public let scopes: [String]

  /// The provider claims that the server copies as they are into the user's `custom_claims`.
  public let customClaimsAllowlist: [String]

  /// Whether the server uses PKCE with the provider.
  public let pkceEnabled: Bool

  /// How the provider's claims map to Supabase user attributes.
  public let attributeMapping: JSONObject

  /// Extra query parameters the server adds to the authorization request.
  public let authorizationParams: [String: String]

  /// Whether users can sign in with the provider.
  public let enabled: Bool

  /// Whether a user can sign in when the provider sends no email address.
  public let emailOptional: Bool

  /// The OIDC issuer. OIDC providers only.
  public let issuer: String?

  /// The URL of the OIDC discovery document, when it is not under ``issuer``.
  public let discoveryURL: URL?

  /// Whether the server skips the ID token nonce check. OIDC providers only.
  public let skipNonceCheck: Bool

  /// The authorization endpoint. OAuth 2.0 providers only.
  public let authorizationURL: URL?

  /// The token endpoint. OAuth 2.0 providers only.
  public let tokenURL: URL?

  /// The userinfo endpoint. OAuth 2.0 providers only.
  public let userinfoURL: URL?

  /// The JSON Web Key Set URL used to verify ID tokens.
  public let jwksURI: URL?

  /// The discovery document the server fetched. OIDC providers only.
  public let discoveryDocument: OIDCDiscoveryDocument?

  /// When the provider was created.
  public let createdAt: Date

  /// When the provider was last updated.
  public let updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id
    case providerType = "provider_type"
    case identifier
    case name
    case clientID = "client_id"
    case acceptableClientIDs = "acceptable_client_ids"
    case scopes
    case customClaimsAllowlist = "custom_claims_allowlist"
    case pkceEnabled = "pkce_enabled"
    case attributeMapping = "attribute_mapping"
    case authorizationParams = "authorization_params"
    case enabled
    case emailOptional = "email_optional"
    case issuer
    case discoveryURL = "discovery_url"
    case skipNonceCheck = "skip_nonce_check"
    case authorizationURL = "authorization_url"
    case tokenURL = "token_url"
    case userinfoURL = "userinfo_url"
    case jwksURI = "jwks_uri"
    case discoveryDocument = "discovery_document"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    providerType = try container.decode(CustomProviderType.self, forKey: .providerType)
    identifier = try container.decode(String.self, forKey: .identifier)
    name = try container.decode(String.self, forKey: .name)
    clientID = try container.decode(String.self, forKey: .clientID)
    // The server sends `null` for an empty list or map.
    acceptableClientIDs =
      try container.decodeIfPresent([String].self, forKey: .acceptableClientIDs) ?? []
    scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
    customClaimsAllowlist =
      try container.decodeIfPresent([String].self, forKey: .customClaimsAllowlist) ?? []
    pkceEnabled = try container.decodeIfPresent(Bool.self, forKey: .pkceEnabled) ?? false
    attributeMapping =
      try container.decodeIfPresent(JSONObject.self, forKey: .attributeMapping) ?? [:]
    authorizationParams =
      try container.decodeIfPresent([String: String].self, forKey: .authorizationParams) ?? [:]
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    emailOptional = try container.decodeIfPresent(Bool.self, forKey: .emailOptional) ?? false
    issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
    discoveryURL = try container.decodeIfPresent(URL.self, forKey: .discoveryURL)
    skipNonceCheck = try container.decodeIfPresent(Bool.self, forKey: .skipNonceCheck) ?? false
    authorizationURL = try container.decodeIfPresent(URL.self, forKey: .authorizationURL)
    tokenURL = try container.decodeIfPresent(URL.self, forKey: .tokenURL)
    userinfoURL = try container.decodeIfPresent(URL.self, forKey: .userinfoURL)
    jwksURI = try container.decodeIfPresent(URL.self, forKey: .jwksURI)
    discoveryDocument = try container.decodeIfPresent(
      OIDCDiscoveryDocument.self, forKey: .discoveryDocument)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }
}

/// The OIDC discovery document the server fetched for a ``CustomProvider``.
public struct OIDCDiscoveryDocument: Decodable, Hashable, Sendable {
  /// The issuer identifier.
  public let issuer: String

  /// The authorization endpoint.
  public let authorizationEndpoint: URL

  /// The token endpoint.
  public let tokenEndpoint: URL

  /// The userinfo endpoint.
  public let userinfoEndpoint: URL?

  /// The JSON Web Key Set URL.
  public let jwksURI: URL

  /// The scopes the provider supports.
  public let scopesSupported: [String]?

  /// The response types the provider supports.
  public let responseTypesSupported: [String]?

  /// The grant types the provider supports.
  public let grantTypesSupported: [String]?

  /// The subject identifier types the provider supports.
  public let subjectTypesSupported: [String]?

  private enum CodingKeys: String, CodingKey {
    case issuer
    case authorizationEndpoint = "authorization_endpoint"
    case tokenEndpoint = "token_endpoint"
    case userinfoEndpoint = "userinfo_endpoint"
    case jwksURI = "jwks_uri"
    case scopesSupported = "scopes_supported"
    case responseTypesSupported = "response_types_supported"
    case grantTypesSupported = "grant_types_supported"
    case subjectTypesSupported = "subject_types_supported"
  }
}

/// The settings for a new custom provider, passed to ``AuthAdminCustomProviders/create(_:)``.
///
/// Use ``oauth2(identifier:name:clientID:clientSecret:authorizationURL:tokenURL:userinfoURL:)``
/// or ``oidc(identifier:name:clientID:clientSecret:issuer:)`` to set the required fields, then
/// set the optional ones.
public struct CreateCustomProviderParams: Encodable, Hashable, Sendable {
  /// Whether the provider uses OAuth 2.0 or OIDC.
  public var providerType: CustomProviderType

  /// The name used to sign in with the provider. It must start with `custom:`.
  public var identifier: String

  /// The name shown to people.
  public var name: String

  /// The OAuth client ID.
  public var clientID: String

  /// The OAuth client secret. The server stores it and never returns it.
  public var clientSecret: String

  /// More client IDs that the server accepts when it checks an ID token.
  public var acceptableClientIDs: [String]?

  /// The scopes to request at the provider.
  public var scopes: [String]?

  /// The provider claims to copy as they are into the user's `custom_claims`.
  public var customClaimsAllowlist: [String]?

  /// Whether to use PKCE with the provider.
  public var pkceEnabled: Bool?

  /// How the provider's claims map to Supabase user attributes.
  public var attributeMapping: JSONObject?

  /// Extra query parameters to add to the authorization request.
  public var authorizationParams: [String: String]?

  /// Whether users can sign in with the provider.
  public var enabled: Bool?

  /// Whether a user can sign in when the provider sends no email address.
  public var emailOptional: Bool?

  /// The OIDC issuer. Required for OIDC providers.
  public var issuer: String?

  /// The URL of the OIDC discovery document, when it is not under ``issuer``.
  public var discoveryURL: URL?

  /// Whether to skip the ID token nonce check. OIDC providers only.
  public var skipNonceCheck: Bool?

  /// The authorization endpoint. Required for OAuth 2.0 providers.
  public var authorizationURL: URL?

  /// The token endpoint. Required for OAuth 2.0 providers.
  public var tokenURL: URL?

  /// The userinfo endpoint. Required for OAuth 2.0 providers.
  public var userinfoURL: URL?

  /// The JSON Web Key Set URL used to verify ID tokens.
  public var jwksURI: URL?

  /// Creates the settings for a new provider. Prefer
  /// ``oauth2(identifier:name:clientID:clientSecret:authorizationURL:tokenURL:userinfoURL:)`` or
  /// ``oidc(identifier:name:clientID:clientSecret:issuer:)``.
  public init(
    providerType: CustomProviderType,
    identifier: String,
    name: String,
    clientID: String,
    clientSecret: String
  ) {
    self.providerType = providerType
    self.identifier = identifier
    self.name = name
    self.clientID = clientID
    self.clientSecret = clientSecret
  }

  /// The settings for an OAuth 2.0 provider.
  public static func oauth2(
    identifier: String,
    name: String,
    clientID: String,
    clientSecret: String,
    authorizationURL: URL,
    tokenURL: URL,
    userinfoURL: URL
  ) -> CreateCustomProviderParams {
    var params = CreateCustomProviderParams(
      providerType: .oauth2,
      identifier: identifier,
      name: name,
      clientID: clientID,
      clientSecret: clientSecret
    )
    params.authorizationURL = authorizationURL
    params.tokenURL = tokenURL
    params.userinfoURL = userinfoURL
    return params
  }

  /// The settings for an OIDC provider.
  ///
  /// The server fetches the discovery document under `issuer` before it creates the provider,
  /// and fails with a `validation_failed` error when it cannot.
  public static func oidc(
    identifier: String,
    name: String,
    clientID: String,
    clientSecret: String,
    issuer: String
  ) -> CreateCustomProviderParams {
    var params = CreateCustomProviderParams(
      providerType: .oidc,
      identifier: identifier,
      name: name,
      clientID: clientID,
      clientSecret: clientSecret
    )
    params.issuer = issuer
    return params
  }

  private enum CodingKeys: String, CodingKey {
    case providerType = "provider_type"
    case identifier
    case name
    case clientID = "client_id"
    case clientSecret = "client_secret"
    case acceptableClientIDs = "acceptable_client_ids"
    case scopes
    case customClaimsAllowlist = "custom_claims_allowlist"
    case pkceEnabled = "pkce_enabled"
    case attributeMapping = "attribute_mapping"
    case authorizationParams = "authorization_params"
    case enabled
    case emailOptional = "email_optional"
    case issuer
    case discoveryURL = "discovery_url"
    case skipNonceCheck = "skip_nonce_check"
    case authorizationURL = "authorization_url"
    case tokenURL = "token_url"
    case userinfoURL = "userinfo_url"
    case jwksURI = "jwks_uri"
  }
}

/// The changes to a custom provider, passed to
/// ``AuthAdminCustomProviders/update(identifier:params:)``.
///
/// The server changes only the fields you set. A field left `nil` keeps its stored value. The
/// provider type and identifier cannot change.
public struct UpdateCustomProviderParams: Encodable, Hashable, Sendable {
  /// The name shown to people.
  public var name: String?

  /// The OAuth client ID.
  public var clientID: String?

  /// A new OAuth client secret.
  public var clientSecret: String?

  /// More client IDs that the server accepts when it checks an ID token.
  public var acceptableClientIDs: [String]?

  /// The scopes to request at the provider.
  public var scopes: [String]?

  /// The provider claims to copy as they are into the user's `custom_claims`.
  public var customClaimsAllowlist: [String]?

  /// Whether to use PKCE with the provider.
  public var pkceEnabled: Bool?

  /// How the provider's claims map to Supabase user attributes.
  public var attributeMapping: JSONObject?

  /// Extra query parameters to add to the authorization request.
  public var authorizationParams: [String: String]?

  /// Whether users can sign in with the provider.
  public var enabled: Bool?

  /// Whether a user can sign in when the provider sends no email address.
  public var emailOptional: Bool?

  /// The OIDC issuer. A change makes the server fetch the discovery document again.
  public var issuer: String?

  /// The URL of the OIDC discovery document. A change makes the server fetch it again.
  public var discoveryURL: URL?

  /// Whether to skip the ID token nonce check. OIDC providers only.
  public var skipNonceCheck: Bool?

  /// The authorization endpoint. OAuth 2.0 providers only.
  public var authorizationURL: URL?

  /// The token endpoint. OAuth 2.0 providers only.
  public var tokenURL: URL?

  /// The userinfo endpoint. OAuth 2.0 providers only.
  public var userinfoURL: URL?

  /// The JSON Web Key Set URL used to verify ID tokens.
  public var jwksURI: URL?

  /// Creates an empty set of changes. Set the fields to change.
  public init(
    name: String? = nil,
    clientID: String? = nil,
    clientSecret: String? = nil,
    acceptableClientIDs: [String]? = nil,
    scopes: [String]? = nil,
    customClaimsAllowlist: [String]? = nil,
    pkceEnabled: Bool? = nil,
    attributeMapping: JSONObject? = nil,
    authorizationParams: [String: String]? = nil,
    enabled: Bool? = nil,
    emailOptional: Bool? = nil,
    issuer: String? = nil,
    discoveryURL: URL? = nil,
    skipNonceCheck: Bool? = nil,
    authorizationURL: URL? = nil,
    tokenURL: URL? = nil,
    userinfoURL: URL? = nil,
    jwksURI: URL? = nil
  ) {
    self.name = name
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.acceptableClientIDs = acceptableClientIDs
    self.scopes = scopes
    self.customClaimsAllowlist = customClaimsAllowlist
    self.pkceEnabled = pkceEnabled
    self.attributeMapping = attributeMapping
    self.authorizationParams = authorizationParams
    self.enabled = enabled
    self.emailOptional = emailOptional
    self.issuer = issuer
    self.discoveryURL = discoveryURL
    self.skipNonceCheck = skipNonceCheck
    self.authorizationURL = authorizationURL
    self.tokenURL = tokenURL
    self.userinfoURL = userinfoURL
    self.jwksURI = jwksURI
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case clientID = "client_id"
    case clientSecret = "client_secret"
    case acceptableClientIDs = "acceptable_client_ids"
    case scopes
    case customClaimsAllowlist = "custom_claims_allowlist"
    case pkceEnabled = "pkce_enabled"
    case attributeMapping = "attribute_mapping"
    case authorizationParams = "authorization_params"
    case enabled
    case emailOptional = "email_optional"
    case issuer
    case discoveryURL = "discovery_url"
    case skipNonceCheck = "skip_nonce_check"
    case authorizationURL = "authorization_url"
    case tokenURL = "token_url"
    case userinfoURL = "userinfo_url"
    case jwksURI = "jwks_uri"
  }
}
