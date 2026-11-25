//
//  AuthAdminSSOTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 25/11/26.
//

import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthAdminSSOTests {
  let transport = RecordingTransport()
  let providerID = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!

  private var providerJSON: String {
    """
    {
      "id": "\(providerID)",
      "resource_id": "acme",
      "disabled": null,
      "saml": {
        "entity_id": "https://idp.acme.example/metadata",
        "metadata_xml": "<EntityDescriptor/>",
        "metadata_url": "https://idp.acme.example/metadata",
        "attribute_mapping": {
          "keys": {
            "email": {"name": "mail"},
            "groups": {"names": ["groups", "roles"], "default": [], "array": true}
          }
        },
        "name_id_format": "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
        "dedicated_scope": true
      },
      "domains": [{"domain": "acme.example"}, {"domain": "acme.test"}],
      "created_at": "2026-11-25T10:00:00Z",
      "updated_at": "2026-11-25T11:00:00Z"
    }
    """
  }

  @Test
  func listProvidersSendsTheFiltersAndDecodesProvidersWithoutMetadata() async throws {
    let responseData = Data(
      """
      {
        "items": [
          {
            "id": "\(providerID)",
            "saml": {"entity_id": "https://idp.acme.example/metadata", "attribute_mapping": {}},
            "domains": null,
            "created_at": "2026-11-25T10:00:00Z",
            "updated_at": "2026-11-25T10:00:00Z"
          }
        ]
      }
      """.utf8)

    transport.stub(
      .get, "admin/sso/providers", query: ["resource_id": "acme", "resource_id_prefix": "ac"],
      data: responseData
    ) {
      #"""
      curl \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/sso/providers?resource_id=acme&resource_id_prefix=ac"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let providers = try await sut.sso.listProviders(resourceID: "acme", resourceIDPrefix: "ac")

    expectNoDifference(
      providers,
      [
        SSOProvider(
          id: providerID,
          isDisabled: false,
          saml: SSOProvider.SAMLSettings(entityID: "https://idp.acme.example/metadata"),
          domains: [],
          createdAt: Date(timeIntervalSince1970: 1_795_600_800),
          updatedAt: Date(timeIntervalSince1970: 1_795_600_800)
        )
      ]
    )
  }

  @Test
  func listProvidersReadsNullItemsAsEmpty() async throws {
    transport.stub(.get, "admin/sso/providers", data: Data(#"{"items": null}"#.utf8))

    let sut = AuthAdminClient.testing(http: transport)

    #expect(try await sut.sso.listProviders().isEmpty)
  }

  @Test
  func createProviderAcceptsCreatedStatus() async throws {
    transport.stub(
      .post, "admin/sso/providers", status: .created, data: Data(providerJSON.utf8)
    ) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "Content-Length: 172" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	--data "{\"attribute_mapping\":{\"keys\":{\"email\":{\"name\":\"mail\"}}},\"domains\":[\"acme.example\"],\"metadata_url\":\"https:\/\/idp.acme.example\/metadata\",\"resource_id\":\"acme\",\"type\":\"saml\"}" \
      	"http://localhost:54321/auth/v1/admin/sso/providers"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    var settings = CreateSSOProvider.saml(
      metadataURL: URL(string: "https://idp.acme.example/metadata")!)
    settings.domains = ["acme.example"]
    settings.attributeMapping = SAMLAttributeMapping(keys: ["email": SAMLAttribute(name: "mail")])
    settings.resourceID = "acme"

    let provider = try await sut.sso.createProvider(settings)

    #expect(provider.id == providerID)
  }

  @Test
  func createProviderFromMetadataXMLSendsTheDocument() throws {
    var settings = CreateSSOProvider.saml(metadataXML: "<EntityDescriptor/>")
    settings.nameIDFormat = .emailAddress
    settings.isDisabled = true
    settings.usesDedicatedScope = true
    let body = try AuthClient.Configuration.jsonEncoder.encode(settings)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

    #expect(
      json?.keys.sorted() == [
        "dedicated_scope", "disabled", "metadata_xml", "name_id_format", "type",
      ])
    #expect(json?["metadata_xml"] as? String == "<EntityDescriptor/>")
    #expect(
      json?["name_id_format"] as? String
        == "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress")
  }

  @Test
  func providerAcceptsAResourceIDAndDecodesEveryField() async throws {
    transport.stub(.get, "admin/sso/providers/resource_acme", data: Data(providerJSON.utf8)) {
      #"""
      curl \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/sso/providers/resource_acme"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let provider = try await sut.sso.provider(id: "resource_acme")

    expectNoDifference(
      provider,
      SSOProvider(
        id: providerID,
        resourceID: "acme",
        isDisabled: false,
        saml: SSOProvider.SAMLSettings(
          entityID: "https://idp.acme.example/metadata",
          metadataXML: "<EntityDescriptor/>",
          metadataURL: URL(string: "https://idp.acme.example/metadata"),
          attributeMapping: SAMLAttributeMapping(keys: [
            "email": SAMLAttribute(name: "mail"),
            "groups": SAMLAttribute(names: ["groups", "roles"], default: [], isArray: true),
          ]),
          nameIDFormat: .persistent,
          usesDedicatedScope: true
        ),
        domains: ["acme.example", "acme.test"],
        createdAt: Date(timeIntervalSince1970: 1_795_600_800),
        updatedAt: Date(timeIntervalSince1970: 1_795_604_400)
      )
    )
  }

  @Test
  func providerDecodesANameIDFormatTheSDKDoesNotKnow() throws {
    let json = Data(
      #"{"entity_id": "e", "name_id_format": "urn:example:nameid-format:future"}"#.utf8)

    let saml = try AuthClient.Configuration.jsonDecoder.decode(
      SSOProvider.SAMLSettings.self, from: json)

    #expect(saml.nameIDFormat?.rawValue == "urn:example:nameid-format:future")
    #expect(saml.attributeMapping.keys.isEmpty)
    #expect(!saml.usesDedicatedScope)
  }

  @Test
  func updateProviderSendsTheChangesToTheProviderPath() async throws {
    transport.stub(
      .put, "admin/sso/providers/\(providerID.uuidString.lowercased())",
      data: Data(providerJSON.utf8)
    ) {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "Content-Length: 89" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	--data "{\"disabled\":true,\"name_id_format\":\"urn:oasis:names:tc:SAML:2.0:nameid-format:persistent\"}" \
      	"http://localhost:54321/auth/v1/admin/sso/providers/859f402d-b3de-4105-a1b9-932836d9193b"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    let provider = try await sut.sso.updateProvider(
      id: providerID.uuidString.lowercased(),
      UpdateSSOProvider(nameIDFormat: .persistent, isDisabled: true))

    #expect(provider.id == providerID)
  }

  @Test
  func updateProviderOmitsFieldsThatAreNotSet() throws {
    let body = try AuthClient.Configuration.jsonEncoder.encode(UpdateSSOProvider())

    #expect(String(decoding: body, as: UTF8.self) == "{}")
  }

  @Test
  func updateProviderSendsEmptyDomainsAndAttributeMapping() throws {
    let body = try AuthClient.Configuration.jsonEncoder.encode(
      UpdateSSOProvider(domains: [], attributeMapping: SAMLAttributeMapping(), resourceID: ""))

    #expect(
      String(decoding: body, as: UTF8.self)
        == #"{"attribute_mapping":{"keys":{}},"domains":[],"resource_id":""}"#)
  }

  @Test
  func deleteProviderReachesTheProviderPath() async throws {
    transport.stub(.delete, "admin/sso/providers/resource_acme", data: Data(providerJSON.utf8)) {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer supabase.secret.key" \
      	--header "X-Client-Info: auth-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: supabase.secret.key" \
      	"http://localhost:54321/auth/v1/admin/sso/providers/resource_acme"
      """#
    }

    let sut = AuthAdminClient.testing(http: transport)

    try await sut.sso.deleteProvider(id: "resource_acme")
  }
}
