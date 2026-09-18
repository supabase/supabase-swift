public import Foundation
import HTTPTypes

/// Admin operations for managing a user's multi-factor authentication factors.
///
/// Access this namespace via ``AuthAdmin/mfa``.
///
/// > Warning: These methods require the secret key. Never expose this key
/// > in a browser or mobile app. Call these methods from a secure server-side environment only.
///
/// ## Topics
///
/// ### Managing factors
/// - ``listFactors(forUser:)``
/// - ``deleteFactor(id:forUser:)``
public struct AuthAdminMFA: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }

  /// Lists the MFA factors enrolled by a user.
  ///
  /// - Parameter userId: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func listFactors(forUser userId: UUID) async throws -> [Factor] {
    try await api.execute(
      HTTPRequest(
        method: .get,
        url: configuration.url.appendingPathComponent("admin/users/\(userId)/factors")
      )
    )
    .decoded(decoder: configuration.resolvedDecoder)
  }

  /// Deletes an MFA factor enrolled by a user, and downgrades that user's sessions to AAL1.
  ///
  /// - Parameters:
  ///   - id: The identifier of the factor to delete, as found on ``Factor/id``.
  ///   - userId: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `secret` key in the client.
  public func deleteFactor(id: String, forUser userId: UUID) async throws {
    _ = try await api.execute(
      HTTPRequest(
        method: .delete,
        url: configuration.url.appendingPathComponent("admin/users/\(userId)/factors/\(id)")
      )
    )
  }
}
