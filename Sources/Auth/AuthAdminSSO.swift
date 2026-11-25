//
//  AuthAdminSSO.swift
//  Auth
//
//  Created by Guilherme Souza on 25/11/26.
//

public import Foundation

/// Admin operations on single sign-on (SAML) identity providers.
///
/// Access this namespace through ``AuthAdminClient/sso``.
///
/// A provider is addressed by its ``SSOProvider/id``, or by `resource_<resourceID>` when it was
/// registered with a ``CreateSSOProvider/resourceID``. SAML sign-in does not need to be turned on
/// for the project to manage providers.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app. Call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Managing providers
/// - ``listProviders(resourceID:resourceIDPrefix:)``
/// - ``createProvider(_:)``
/// - ``provider(id:)``
/// - ``updateProvider(id:_:)``
/// - ``deleteProvider(id:)``
///
/// ### Models
/// - ``SSOProvider``
/// - ``CreateSSOProvider``
/// - ``UpdateSSOProvider``
/// - ``SSOProviderType``
/// - ``SAMLAttributeMapping``
/// - ``SAMLAttribute``
/// - ``SAMLNameIDFormat``
public struct AuthAdminSSO: Sendable {
  let admin: AuthAdminClient

  /// Lists the SSO providers.
  ///
  /// The providers in the result have no ``SSOProvider/SAMLSettings/metadataXML``. Use
  /// ``provider(id:)`` to read it.
  ///
  /// - Parameters:
  ///   - resourceID: Lists only the provider with this resource ID.
  ///   - resourceIDPrefix: Lists only the providers whose resource ID starts with this prefix.
  ///     The server ignores it when `resourceID` is set.
  /// - Returns: The SSO providers.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  public func listProviders(
    resourceID: String? = nil,
    resourceIDPrefix: String? = nil
  ) async throws -> [SSOProvider] {
    try await admin.api.execute(
      admin.authAPI.adminListSSOProviders(
        resourceID: resourceID, resourceIDPrefix: resourceIDPrefix))
  }

  /// Registers an SSO provider.
  ///
  /// When the settings give a ``CreateSSOProvider/metadataURL``, the server fetches the metadata
  /// before it answers, so the call takes as long as that request.
  ///
  /// - Parameter provider: The settings for the provider.
  /// - Returns: The provider that the server created.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  @discardableResult
  public func createProvider(_ provider: CreateSSOProvider) async throws -> SSOProvider {
    try await admin.api.execute(admin.authAPI.adminCreateSSOProvider(provider))
  }

  /// Gets an SSO provider, with its SAML metadata.
  ///
  /// - Parameter id: The provider's ``SSOProvider/id``, or `resource_<resourceID>`.
  /// - Returns: The SSO provider.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  public func provider(id: String) async throws -> SSOProvider {
    try await admin.api.execute(admin.authAPI.adminSSOProvider(id: id))
  }

  /// Updates an SSO provider.
  ///
  /// The server changes only the fields you set, except ``UpdateSSOProvider/nameIDFormat``,
  /// which it clears when you leave it `nil`. When the changes give a
  /// ``UpdateSSOProvider/metadataURL``, the server fetches the metadata before it answers.
  ///
  /// - Parameters:
  ///   - id: The provider's ``SSOProvider/id``, or `resource_<resourceID>`.
  ///   - changes: The fields to change.
  /// - Returns: The updated provider.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  @discardableResult
  public func updateProvider(id: String, _ changes: UpdateSSOProvider) async throws -> SSOProvider {
    try await admin.api.execute(admin.authAPI.adminUpdateSSOProvider(id: id, changes))
  }

  /// Deletes an SSO provider and its domains.
  ///
  /// - Parameter id: The provider's ``SSOProvider/id``, or `resource_<resourceID>`.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  public func deleteProvider(id: String) async throws {
    try await admin.api.execute(admin.authAPI.adminDeleteSSOProvider(id: id))
  }
}
