//
//  AuthAdminSSOIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 25/11/26.
//

import CustomDump
import Foundation
import Testing

@testable import Auth

/// The admin SSO provider API against the local stack. Managing providers does not need SAML
/// sign-in to be turned on, so the stack needs no SAML settings.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct AuthAdminSSOIntegrationTests {
  let admin = AuthClientIntegrationTests.makeAdminClient()

  @Test
  func adminCreatesReadsListsAndDeletesAProvider() async throws {
    let fixture = Fixture()

    var settings = CreateSSOProvider.saml(metadataXML: fixture.metadataXML)
    settings.domains = [fixture.domain]
    settings.attributeMapping = SAMLAttributeMapping(keys: ["email": SAMLAttribute(name: "mail")])
    settings.nameIDFormat = .persistent
    settings.resourceID = fixture.resourceID
    let created = try await admin.sso.createProvider(settings)

    #expect(created.resourceID == fixture.resourceID)
    #expect(!created.isDisabled)
    #expect(created.domains == [fixture.domain])
    #expect(created.saml.entityID == fixture.entityID)
    #expect(created.saml.nameIDFormat == .persistent)
    #expect(created.saml.attributeMapping.keys["email"]?.name == "mail")

    // The get, update, and delete paths accept the UUID or `resource_<resourceID>`.
    let byID = try await admin.sso.provider(id: created.id.uuidString)
    let byResourceID = try await admin.sso.provider(id: "resource_\(fixture.resourceID)")
    #expect(byID.id == created.id)
    #expect(byResourceID.id == created.id)
    #expect(byID.saml.metadataXML == fixture.metadataXML)

    // The list leaves the metadata out.
    let listed = try await admin.sso.listProviders(resourceID: fixture.resourceID)
    expectNoDifference(listed.map(\.id), [created.id])
    #expect(listed.first?.saml.metadataXML == nil)
    let byPrefix = try await admin.sso.listProviders(resourceIDPrefix: fixture.resourcePrefix)
    #expect(byPrefix.map(\.id).contains(created.id))

    try await admin.sso.deleteProvider(id: "resource_\(fixture.resourceID)")

    let error = await #expect(throws: AuthError.self) {
      try await admin.sso.provider(id: created.id.uuidString)
    }
    #expect(error?.code?.rawValue == "sso_provider_not_found")
  }

  @Test
  func adminUpdateKeepsUnsetFieldsAndClearsEmptyOnes() async throws {
    let fixture = Fixture()

    var settings = CreateSSOProvider.saml(metadataXML: fixture.metadataXML)
    settings.domains = [fixture.domain]
    settings.attributeMapping = SAMLAttributeMapping(keys: ["email": SAMLAttribute(name: "mail")])
    settings.nameIDFormat = .emailAddress
    let created = try await admin.sso.createProvider(settings)
    let id = created.id.uuidString

    // Unset domains and mapping keep their stored values. The format is sent to keep it.
    let disabled = try await admin.sso.updateProvider(
      id: id, UpdateSSOProvider(nameIDFormat: .emailAddress, isDisabled: true))
    #expect(disabled.isDisabled)
    #expect(disabled.domains == [fixture.domain])
    #expect(disabled.saml.attributeMapping.keys["email"]?.name == "mail")
    #expect(disabled.saml.nameIDFormat == .emailAddress)

    // Empty values clear the domains and the mapping.
    let cleared = try await admin.sso.updateProvider(
      id: id,
      UpdateSSOProvider(
        domains: [], attributeMapping: SAMLAttributeMapping(), nameIDFormat: .emailAddress))
    #expect(cleared.domains.isEmpty)
    #expect(cleared.saml.attributeMapping.keys.isEmpty)
    #expect(cleared.saml.nameIDFormat == .emailAddress)

    // A `nil` format clears the stored one. The server saves a format change only with a
    // metadata or mapping change (`adminSSOProvidersUpdate` in supabase/auth), so this sets a
    // mapping too.
    let noFormat = try await admin.sso.updateProvider(
      id: id,
      UpdateSSOProvider(
        attributeMapping: SAMLAttributeMapping(keys: ["name": SAMLAttribute(name: "cn")])))
    #expect(noFormat.saml.nameIDFormat == nil)
    #expect(noFormat.saml.attributeMapping.keys["name"]?.name == "cn")
    #expect(noFormat.isDisabled)
    #expect(try await admin.sso.provider(id: id).saml.nameIDFormat == nil)

    try await admin.sso.deleteProvider(id: id)
  }

  /// A unique identity provider for one test, so tests and reruns never collide on the entity
  /// ID, the domain, or the resource ID.
  private struct Fixture {
    let suffix = UUID().uuidString.lowercased()

    var entityID: String { "https://idp-\(suffix).example.test/metadata" }
    var domain: String { "sso-\(suffix).example.test" }
    var resourcePrefix: String { "swift-sdk-" }
    var resourceID: String { "\(resourcePrefix)\(suffix)" }

    var metadataXML: String {
      """
      <EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="\(entityID)">
        <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
          <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" \
      Location="https://idp-\(suffix).example.test/sso"/>
        </IDPSSODescriptor>
      </EntityDescriptor>
      """
    }
  }
}
