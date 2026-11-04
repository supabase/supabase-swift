//
//  AuthAdminCustomProviders.swift
//  Auth
//
//  Created by Guilherme Souza on 03/11/26.
//

public import Foundation

/// Admin operations on custom OAuth 2.0 and OIDC providers.
///
/// Access this namespace through ``AuthAdminClient/customProviders``.
///
/// ## Topics
///
/// ### Managing providers
/// - ``list(type:)``
/// - ``create(_:)``
/// - ``provider(identifier:)``
/// - ``update(identifier:params:)``
/// - ``delete(identifier:)``
public struct AuthAdminCustomProviders: Sendable {
  let admin: AuthAdminClient

  /// Lists the custom providers.
  ///
  /// - Parameter type: Lists only the providers of this type. `nil` lists every provider.
  public func list(type: CustomProviderType? = nil) async throws -> [CustomProvider] {
    try await admin.api.execute(admin.authAPI.adminListCustomProviders(type: type))
  }

  /// Creates a custom provider.
  ///
  /// For an OIDC provider, the server fetches the discovery document before it answers. The call
  /// fails with a `validation_failed` error when the document is unreachable or invalid, or when
  /// its issuer does not match.
  ///
  /// - Parameter params: The settings for the provider.
  @discardableResult
  public func create(_ params: CreateCustomProviderParams) async throws -> CustomProvider {
    try await admin.api.execute(admin.authAPI.adminCreateCustomProvider(params: params))
  }

  /// Gets a custom provider.
  ///
  /// - Parameter identifier: The provider's ``CustomProvider/identifier``, such as
  ///   `custom:acme`.
  public func provider(identifier: String) async throws -> CustomProvider {
    try await admin.api.execute(admin.authAPI.adminCustomProvider(identifier: identifier))
  }

  /// Updates a custom provider. The server changes only the fields you set.
  ///
  /// When the issuer or discovery URL of an OIDC provider changes, the server fetches the
  /// discovery document again, and can fail as ``create(_:)`` does.
  ///
  /// - Parameters:
  ///   - identifier: The provider's ``CustomProvider/identifier``.
  ///   - params: The fields to change.
  @discardableResult
  public func update(
    identifier: String,
    params: UpdateCustomProviderParams
  ) async throws -> CustomProvider {
    try await admin.api.execute(
      admin.authAPI.adminUpdateCustomProvider(identifier: identifier, params: params))
  }

  /// Deletes a custom provider.
  ///
  /// - Parameter identifier: The provider's ``CustomProvider/identifier``.
  public func delete(identifier: String) async throws {
    try await admin.api.execute(admin.authAPI.adminDeleteCustomProvider(identifier: identifier))
  }
}
