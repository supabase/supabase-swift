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
/// - ``update(identifier:_:)``
/// - ``delete(identifier:)``
public struct AuthAdminCustomProviders: Sendable {
  let admin: AuthAdminClient

  /// Lists the custom providers.
  ///
  /// - Parameter type: Lists only the providers of this type. `nil` lists every provider.
  /// - Returns: The custom providers.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  public func list(type: CustomProviderType? = nil) async throws -> [CustomProvider] {
    try await admin.api.execute(admin.authAPI.adminListCustomProviders(type: type))
  }

  /// Creates a custom provider.
  ///
  /// For an OIDC provider, the server fetches the discovery document before it answers. The call
  /// fails with a `validation_failed` error when the document is unreachable or invalid, or when
  /// its issuer does not match.
  ///
  /// - Parameter provider: The settings for the provider.
  /// - Returns: The provider that the server created.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  @discardableResult
  public func create(_ provider: CreateCustomProvider) async throws -> CustomProvider {
    try await admin.api.execute(admin.authAPI.adminCreateCustomProvider(provider))
  }

  /// Gets a custom provider.
  ///
  /// - Parameter identifier: The provider's ``CustomProvider/identifier``, such as
  ///   `custom:acme`.
  /// - Returns: The custom provider.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
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
  ///   - changes: The fields to change.
  /// - Returns: The updated provider.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  @discardableResult
  public func update(
    identifier: String,
    _ changes: UpdateCustomProvider
  ) async throws -> CustomProvider {
    try await admin.api.execute(
      admin.authAPI.adminUpdateCustomProvider(identifier: identifier, changes))
  }

  /// Deletes a custom provider.
  ///
  /// - Parameter identifier: The provider's ``CustomProvider/identifier``.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  public func delete(identifier: String) async throws {
    try await admin.api.execute(admin.authAPI.adminDeleteCustomProvider(identifier: identifier))
  }
}
