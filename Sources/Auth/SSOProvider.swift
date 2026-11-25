//
//  SSOProvider.swift
//  Auth
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Foundation
public import Helpers

/// The protocol an SSO identity provider speaks.
public struct SSOProviderType: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The protocol name as the server reads it, such as `"saml"`.
  public let rawValue: String

  /// Creates an ``SSOProviderType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``SSOProviderType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A SAML 2.0 identity provider.
  public static let saml: SSOProviderType = "saml"
}

/// The format of the SAML `NameID` that Supabase Auth asks the identity provider for.
public struct SAMLNameIDFormat: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The format URN, such as `"urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"`.
  public let rawValue: String

  /// Creates a ``SAMLNameIDFormat`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``SAMLNameIDFormat`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A stable, opaque identifier for the user.
  public static let persistent: SAMLNameIDFormat =
    "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"

  /// The user's email address.
  public static let emailAddress: SAMLNameIDFormat =
    "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"

  /// A one-time identifier that changes on every sign-in.
  public static let transient: SAMLNameIDFormat =
    "urn:oasis:names:tc:SAML:2.0:nameid-format:transient"

  /// Any format the identity provider chooses.
  public static let unspecified: SAMLNameIDFormat =
    "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
}

/// How the attributes of a SAML assertion map to the claims of a Supabase user.
public struct SAMLAttributeMapping: Codable, Hashable, Sendable {
  /// The mapping of each user claim to the SAML attribute that fills it.
  ///
  /// An empty map in ``UpdateSSOProvider/attributeMapping`` clears the stored mapping.
  public var keys: [String: SAMLAttribute]

  /// Creates a ``SAMLAttributeMapping``.
  ///
  /// - Parameter keys: The mapping of each user claim to the SAML attribute that fills it.
  public init(keys: [String: SAMLAttribute] = [:]) {
    self.keys = keys
  }

  private enum CodingKeys: String, CodingKey {
    case keys
  }

  /// Decodes a mapping. A `keys` field that the server omits becomes an empty map.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keys = try container.decodeIfPresent([String: SAMLAttribute].self, forKey: .keys) ?? [:]
  }
}

/// The SAML attribute, or attributes, that fill one claim of a Supabase user.
public struct SAMLAttribute: Codable, Hashable, Sendable {
  /// The name of the SAML attribute to read.
  public var name: String?

  /// The names of SAML attributes to read, in order. The server uses the first one present.
  public var names: [String]?

  /// The value to use when the assertion has none of the attributes.
  public var `default`: JSONValue?

  /// Whether the claim keeps every value of the attribute as an array.
  public var isArray: Bool?

  /// Creates a ``SAMLAttribute``.
  ///
  /// - Parameters:
  ///   - name: The name of the SAML attribute to read.
  ///   - names: The names of SAML attributes to read, in order.
  ///   - default: The value to use when the assertion has none of the attributes.
  ///   - isArray: Whether the claim keeps every value of the attribute as an array.
  public init(
    name: String? = nil,
    names: [String]? = nil,
    default: JSONValue? = nil,
    isArray: Bool? = nil
  ) {
    self.name = name
    self.names = names
    self.default = `default`
    self.isArray = isArray
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case names
    case `default`
    case isArray = "array"
  }
}

/// A single sign-on identity provider registered in Supabase Auth.
///
/// Users sign in with it through ``AuthClient/signInWithSSO(_:options:presenter:)``, with an
/// ``SSOTarget`` that names the provider's ``id`` or one of its ``domains``.
public struct SSOProvider: Decodable, Hashable, Sendable, Identifiable {
  /// The provider's unique ID.
  public var id: UUID

  /// The resource ID the provider was registered with, if any. You can address the provider as
  /// `resource_<resourceID>` in place of its ID.
  public var resourceID: String?

  /// Whether users cannot sign in with the provider.
  public var isDisabled: Bool

  /// The provider's SAML settings.
  public var saml: SAMLSettings

  /// The email domains whose users sign in with the provider.
  public var domains: [String]

  /// When the provider was created.
  public var createdAt: Date

  /// When the provider was last updated.
  public var updatedAt: Date

  /// Creates an ``SSOProvider``.
  public init(
    id: UUID,
    resourceID: String? = nil,
    isDisabled: Bool,
    saml: SAMLSettings,
    domains: [String],
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.resourceID = resourceID
    self.isDisabled = isDisabled
    self.saml = saml
    self.domains = domains
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case resourceID = "resource_id"
    case isDisabled = "disabled"
    case saml
    case domains
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  private struct Domain: Decodable {
    let domain: String
  }

  /// Decodes a provider. A `disabled` flag that the server sends as `null` becomes `false`, and
  /// a `null` domain list becomes empty.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    resourceID = try container.decodeIfPresent(String.self, forKey: .resourceID)
    isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled) ?? false
    saml = try container.decode(SAMLSettings.self, forKey: .saml)
    domains = try container.decodeIfPresent([Domain].self, forKey: .domains)?.map(\.domain) ?? []
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }

  /// The SAML settings of an ``SSOProvider``.
  public struct SAMLSettings: Decodable, Hashable, Sendable {
    /// The identity provider's entity ID, read from its metadata.
    public var entityID: String

    /// The identity provider's SAML metadata document.
    ///
    /// `nil` in the result of ``AuthAdminSSO/listProviders(resourceID:resourceIDPrefix:)``,
    /// which leaves the metadata out. ``AuthAdminSSO/provider(id:)`` returns it.
    public var metadataXML: String?

    /// The URL the server fetched the metadata from, if the provider was registered with one.
    public var metadataURL: URL?

    /// How the attributes of a SAML assertion map to the claims of a Supabase user.
    public var attributeMapping: SAMLAttributeMapping

    /// The `NameID` format the server asks for, if one is set.
    public var nameIDFormat: SAMLNameIDFormat?

    /// Whether the provider has an entity ID of its own, scoped to this provider.
    public var usesDedicatedScope: Bool

    /// Creates the SAML settings of a provider.
    public init(
      entityID: String,
      metadataXML: String? = nil,
      metadataURL: URL? = nil,
      attributeMapping: SAMLAttributeMapping = SAMLAttributeMapping(),
      nameIDFormat: SAMLNameIDFormat? = nil,
      usesDedicatedScope: Bool = false
    ) {
      self.entityID = entityID
      self.metadataXML = metadataXML
      self.metadataURL = metadataURL
      self.attributeMapping = attributeMapping
      self.nameIDFormat = nameIDFormat
      self.usesDedicatedScope = usesDedicatedScope
    }

    private enum CodingKeys: String, CodingKey {
      case entityID = "entity_id"
      case metadataXML = "metadata_xml"
      case metadataURL = "metadata_url"
      case attributeMapping = "attribute_mapping"
      case nameIDFormat = "name_id_format"
      case usesDedicatedScope = "dedicated_scope"
    }

    /// Decodes the SAML settings. A field that the server omits becomes `nil`, empty, or
    /// `false`.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      entityID = try container.decode(String.self, forKey: .entityID)
      metadataXML = try container.decodeIfPresent(String.self, forKey: .metadataXML)
      metadataURL = try container.decodeIfPresent(URL.self, forKey: .metadataURL)
      attributeMapping =
        try container.decodeIfPresent(SAMLAttributeMapping.self, forKey: .attributeMapping)
        ?? SAMLAttributeMapping()
      nameIDFormat = try container.decodeIfPresent(SAMLNameIDFormat.self, forKey: .nameIDFormat)
      usesDedicatedScope =
        try container.decodeIfPresent(Bool.self, forKey: .usesDedicatedScope) ?? false
    }
  }
}

/// The settings for a new SSO provider, passed to ``AuthAdminSSO/createProvider(_:)``.
///
/// Use ``saml(metadataURL:)`` or ``saml(metadataXML:)`` to set the required fields, then set the
/// optional ones.
public struct CreateSSOProvider: Encodable, Hashable, Sendable {
  /// The protocol the provider speaks.
  public var type: SSOProviderType

  /// A URL to fetch the identity provider's SAML metadata from. The server fetches it before it
  /// answers. Set this or ``metadataXML``, not both.
  public var metadataURL: URL?

  /// The identity provider's SAML metadata document. Set this or ``metadataURL``, not both.
  public var metadataXML: String?

  /// The email domains whose users sign in with the provider.
  public var domains: [String]?

  /// How the attributes of a SAML assertion map to the claims of a Supabase user.
  public var attributeMapping: SAMLAttributeMapping?

  /// The `NameID` format to ask the identity provider for.
  public var nameIDFormat: SAMLNameIDFormat?

  /// An ID of your own for the provider. You can then address the provider as
  /// `resource_<resourceID>` in place of its ID.
  public var resourceID: String?

  /// Whether users cannot sign in with the provider.
  public var isDisabled: Bool?

  /// Whether the provider gets an entity ID of its own, scoped to this provider. It cannot
  /// change after the provider is created.
  public var usesDedicatedScope: Bool?

  /// Creates the settings for a new provider. Prefer ``saml(metadataURL:)`` or
  /// ``saml(metadataXML:)``.
  ///
  /// - Parameter type: The protocol the provider speaks.
  public init(type: SSOProviderType) {
    self.type = type
  }

  /// The settings for a SAML provider whose metadata the server fetches from a URL.
  ///
  /// - Parameter metadataURL: The URL of the identity provider's SAML metadata.
  /// - Returns: The settings, ready for the optional fields.
  public static func saml(metadataURL: URL) -> CreateSSOProvider {
    var provider = CreateSSOProvider(type: .saml)
    provider.metadataURL = metadataURL
    return provider
  }

  /// The settings for a SAML provider from its metadata document.
  ///
  /// - Parameter metadataXML: The identity provider's SAML metadata document.
  /// - Returns: The settings, ready for the optional fields.
  public static func saml(metadataXML: String) -> CreateSSOProvider {
    var provider = CreateSSOProvider(type: .saml)
    provider.metadataXML = metadataXML
    return provider
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case metadataURL = "metadata_url"
    case metadataXML = "metadata_xml"
    case domains
    case attributeMapping = "attribute_mapping"
    case nameIDFormat = "name_id_format"
    case resourceID = "resource_id"
    case isDisabled = "disabled"
    case usesDedicatedScope = "dedicated_scope"
  }
}

/// The changes to an SSO provider, passed to ``AuthAdminSSO/updateProvider(id:_:)``.
///
/// The server changes only the fields you set, with one exception: ``nameIDFormat``. When it is
/// `nil`, the server clears the stored format. To keep the format, set it to the provider's
/// current ``SSOProvider/SAMLSettings/nameIDFormat``.
public struct UpdateSSOProvider: Encodable, Hashable, Sendable {
  /// A new URL to fetch the identity provider's SAML metadata from. The server fetches it before
  /// it answers. The entity ID in the metadata must not change.
  public var metadataURL: URL?

  /// A new SAML metadata document. The entity ID in the metadata must not change.
  public var metadataXML: String?

  /// The email domains whose users sign in with the provider. They replace the stored domains,
  /// so an empty array removes every domain. `nil` keeps the stored domains.
  public var domains: [String]?

  /// The new attribute mapping. A mapping with empty ``SAMLAttributeMapping/keys`` clears the
  /// stored mapping. `nil` keeps it.
  public var attributeMapping: SAMLAttributeMapping?

  /// The `NameID` format to ask the identity provider for. `nil` clears the stored format.
  public var nameIDFormat: SAMLNameIDFormat?

  /// The provider's new resource ID. An empty string removes it. `nil` keeps it.
  public var resourceID: String?

  /// Whether users cannot sign in with the provider. `nil` keeps the stored value.
  public var isDisabled: Bool?

  /// Creates a set of changes. Set the fields to change.
  ///
  /// - Parameters:
  ///   - metadataURL: A new URL to fetch the SAML metadata from.
  ///   - metadataXML: A new SAML metadata document.
  ///   - domains: The email domains that replace the stored domains.
  ///   - attributeMapping: The new attribute mapping.
  ///   - nameIDFormat: The `NameID` format. `nil` clears the stored format.
  ///   - resourceID: The new resource ID. An empty string removes it.
  ///   - isDisabled: Whether users cannot sign in with the provider.
  public init(
    metadataURL: URL? = nil,
    metadataXML: String? = nil,
    domains: [String]? = nil,
    attributeMapping: SAMLAttributeMapping? = nil,
    nameIDFormat: SAMLNameIDFormat? = nil,
    resourceID: String? = nil,
    isDisabled: Bool? = nil
  ) {
    self.metadataURL = metadataURL
    self.metadataXML = metadataXML
    self.domains = domains
    self.attributeMapping = attributeMapping
    self.nameIDFormat = nameIDFormat
    self.resourceID = resourceID
    self.isDisabled = isDisabled
  }

  private enum CodingKeys: String, CodingKey {
    case metadataURL = "metadata_url"
    case metadataXML = "metadata_xml"
    case domains
    case attributeMapping = "attribute_mapping"
    case nameIDFormat = "name_id_format"
    case resourceID = "resource_id"
    case isDisabled = "disabled"
  }
}
