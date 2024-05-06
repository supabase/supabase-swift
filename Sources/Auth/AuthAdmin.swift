//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

import _Helpers
import Foundation

public struct AuthAdmin: Sendable {
  var configuration: AuthClient.Configuration { Current.configuration }
  var api: APIClient { Current.api }
  var encoder: JSONEncoder { Current.encoder }

  /// Delete a user. Requires `service_role` key.
  /// - Parameter id: The id of the user you want to delete.
  /// - Parameter shouldSoftDelete: If true, then the user will be soft-deleted (setting
  /// `deleted_at` to the current timestamp and disabling their account while preserving their data)
  /// from the auth schema.
  ///
  /// - Warning: Never expose your `service_role` key on the client.
  public func deleteUser(id: String, shouldSoftDelete: Bool = false) async throws {
    _ = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users/\(id)"),
        method: .delete,
        body: encoder.encode(
          DeleteUserRequest(shouldSoftDelete: shouldSoftDelete)
        )
      )
    )
  }
}
