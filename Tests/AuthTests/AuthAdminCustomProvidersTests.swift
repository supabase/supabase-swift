//
//  AuthAdminCustomProvidersTests.swift
//  AuthTests
//
//  Created by Guilherme Souza on 03/11/26.
//

import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthAdminCustomProvidersTests {
  private func makeSUT(status: HTTPResponse.Status = .ok, body: String) -> AuthAdminClient {
    let transport = RecordingTransport { _, _ in (HTTPResponse(status: status), Data(body.utf8)) }
    return .testing(http: transport)
  }

  @Test
  func listReadsNullFieldsAsEmpty() async throws {
    let sut = makeSUT(
      body: """
        {
          "providers": [
            {
              "id": "859f402d-b3de-4105-a1b9-932836d9193b",
              "provider_type": "oauth2",
              "identifier": "custom:acme",
              "name": "Acme",
              "client_id": "client-id",
              "acceptable_client_ids": null,
              "scopes": null,
              "pkce_enabled": true,
              "attribute_mapping": null,
              "custom_claims_allowlist": null,
              "authorization_params": null,
              "enabled": true,
              "email_optional": false,
              "skip_nonce_check": false,
              "authorization_url": "https://acme.example.com/authorize",
              "token_url": "https://acme.example.com/token",
              "userinfo_url": "https://acme.example.com/userinfo",
              "created_at": "2026-11-03T10:00:00Z",
              "updated_at": "2026-11-03T10:00:00Z"
            }
          ]
        }
        """)

    let providers = try await sut.customProviders.list()

    let provider = try #require(providers.first)
    #expect(provider.providerType == .oauth2)
    #expect(provider.identifier == "custom:acme")
    #expect(provider.acceptableClientIDs.isEmpty)
    #expect(provider.scopes.isEmpty)
    #expect(provider.customClaimsAllowlist.isEmpty)
    #expect(provider.attributeMapping.isEmpty)
    #expect(provider.authorizationParams.isEmpty)
    #expect(provider.tokenURL == URL(string: "https://acme.example.com/token"))
    #expect(provider.issuer == nil)
    #expect(provider.discoveryDocument == nil)
  }

  @Test
  func listReadsNullProvidersAsEmpty() async throws {
    let sut = makeSUT(body: #"{"providers": null}"#)

    #expect(try await sut.customProviders.list().isEmpty)
  }

  @Test
  func providerDecodesAnOIDCProvider() async throws {
    let sut = makeSUT(
      body: """
        {
          "id": "859f402d-b3de-4105-a1b9-932836d9193b",
          "provider_type": "oidc",
          "identifier": "custom:corp",
          "name": "Corp",
          "client_id": "client-id",
          "acceptable_client_ids": ["other-client"],
          "scopes": ["openid", "email"],
          "pkce_enabled": true,
          "attribute_mapping": {"keys": {"email": {"name": "mail"}}},
          "custom_claims_allowlist": ["groups", "org_id"],
          "authorization_params": {"prompt": "consent"},
          "enabled": true,
          "email_optional": true,
          "issuer": "https://corp.example.com",
          "skip_nonce_check": false,
          "discovery_document": {
            "issuer": "https://corp.example.com",
            "authorization_endpoint": "https://corp.example.com/authorize",
            "token_endpoint": "https://corp.example.com/token",
            "jwks_uri": "https://corp.example.com/jwks",
            "scopes_supported": ["openid", "email"]
          },
          "created_at": "2026-11-03T10:00:00Z",
          "updated_at": "2026-11-03T11:00:00Z"
        }
        """)

    let provider = try await sut.customProviders.provider(identifier: "custom:corp")

    #expect(provider.providerType == .oidc)
    #expect(provider.acceptableClientIDs == ["other-client"])
    #expect(provider.customClaimsAllowlist == ["groups", "org_id"])
    #expect(provider.authorizationParams == ["prompt": "consent"])
    #expect(provider.attributeMapping["keys"]?.objectValue?["email"] != nil)
    #expect(provider.issuer == "https://corp.example.com")
    expectNoDifference(
      provider.discoveryDocument,
      OIDCDiscoveryDocument(
        issuer: "https://corp.example.com",
        authorizationEndpoint: URL(string: "https://corp.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://corp.example.com/token")!,
        userinfoEndpoint: nil,
        jwksURI: URL(string: "https://corp.example.com/jwks")!,
        scopesSupported: ["openid", "email"],
        responseTypesSupported: nil,
        grantTypesSupported: nil,
        subjectTypesSupported: nil
      )
    )
  }

  @Test
  func updateSendsOnlyTheFieldsSet() throws {
    let body = try AuthClient.Configuration.jsonEncoder.encode(
      UpdateCustomProviderParams(
        clientID: "new-client", customClaimsAllowlist: [], jwksURI: URL(string: "https://j.example")
      ))
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

    #expect(json?.keys.sorted() == ["client_id", "custom_claims_allowlist", "jwks_uri"])
    #expect((json?["custom_claims_allowlist"] as? [String])?.isEmpty == true)
  }
}
