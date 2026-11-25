//
//  AuthAdminMFA.swift
//
//
//  Created by Ranbir Singh on 16/09/26.
//

public import Foundation

/// Admin operations for managing a user's multi-factor authentication factors.
///
/// Access this namespace via ``AuthAdminClient/mfa``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app. Call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Managing factors
/// - ``listFactors(forUser:)``
/// - ``updateFactor(id:forUser:_:)``
/// - ``deleteFactor(id:forUser:)``
/// - ``AdminUpdateFactor``
public struct AuthAdminMFA: Sendable {
  let admin: AuthAdminClient

  var api: APIClient { admin.api }
  var authAPI: AuthAPI { admin.authAPI }

  /// Lists the MFA factors enrolled by a user.
  ///
  /// - Parameter userID: The user's unique identifier.
  /// - Returns: The user's factors.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func listFactors(forUser userID: UUID) async throws -> [Factor] {
    try await api.execute(authAPI.adminListFactors(userID: userID))
  }

  /// Updates an MFA factor enrolled by a user. The server changes only the fields you set.
  ///
  /// This is the only way to rename a factor after enrollment. The server answers with success
  /// and an unchanged factor when `changes` is empty, and it ignores ``AdminUpdateFactor/phone``
  /// on a factor that is not a phone factor.
  ///
  /// - Parameters:
  ///   - id: The identifier of the factor to update, as found on ``Factor/id``.
  ///   - userID: The user's unique identifier.
  ///   - changes: The fields to change.
  /// - Returns: The updated factor.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  @discardableResult
  public func updateFactor(
    id: UUID,
    forUser userID: UUID,
    _ changes: AdminUpdateFactor
  ) async throws -> Factor {
    try await api.execute(authAPI.adminUpdateFactor(id: id, userID: userID, changes))
  }

  /// Deletes an MFA factor enrolled by a user, and downgrades that user's sessions to AAL1.
  ///
  /// - Parameters:
  ///   - id: The identifier of the factor to delete, as found on ``Factor/id``.
  ///   - userID: The user's unique identifier.
  /// - Throws: ``AuthError`` when the request fails. `CancellationError` when the task is
  ///   cancelled.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func deleteFactor(id: UUID, forUser userID: UUID) async throws {
    try await api.execute(authAPI.adminDeleteFactor(id: id, userID: userID))
  }
}

/// The changes for ``AuthAdminMFA/updateFactor(id:forUser:_:)``. The server changes only the
/// fields you set.
public struct AdminUpdateFactor: Encodable, Hashable, Sendable {
  /// The factor's new friendly name.
  public var friendlyName: String?

  /// The new phone number that receives the codes of a ``FactorType/phone`` factor. The server
  /// ignores it on other factor types.
  public var phone: String?

  /// Creates a set of changes. Set the fields to change.
  ///
  /// - Parameters:
  ///   - friendlyName: The factor's new friendly name.
  ///   - phone: The new phone number of a phone factor.
  public init(friendlyName: String? = nil, phone: String? = nil) {
    self.friendlyName = friendlyName
    self.phone = phone
  }

  private enum CodingKeys: String, CodingKey {
    case friendlyName = "friendly_name"
    case phone
  }
}
