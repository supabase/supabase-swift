//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

import Foundation
import HTTPTypes
import Helpers

public struct AuthAdmin: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].encoder }

  /// Get user by id.
  /// - Parameter uid: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the browser.
  public func getUserById(_ uid: String) async throws -> User {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users/\(uid)"),
        method: .get
      )
    ).decoded(decoder: configuration.decoder)
  }

  /// Updates the user data.
  /// - Parameters:
  ///   - uid: The user id you want to update.
  ///   - attributes: The data you want to update.
  @discardableResult
  public func updateUserById(_ uid: String, attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users/\(uid)"),
        method: .put,
        body: configuration.encoder.encode(attributes)
      )
    ).decoded(decoder: configuration.decoder)
  }

  /// Creates a new user.
  ///
  /// - To confirm the user's email address or phone number, set ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` to `true`. Both arguments default to `false`.
  /// - ``createUser(attributes:)`` will not send a confirmation email to the user. You can use ``inviteUserByEmail(_:data:redirectTo:)`` if you want to send them an email invite instead.
  /// - If you are sure that the created user's email or phone number is legitimate and verified, you can set the ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` param to true.
  /// - Warning: Never expose your `service_role` key on the client.
  @discardableResult
  public func createUser(attributes: AdminUserAttributes) async throws -> User {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users"),
        method: .post,
        body: encoder.encode(attributes)
      )
    )
    .decoded(decoder: configuration.decoder)
  }

  /// Sends an invite link to an email address.
  ///
  /// - Sends an invite link to the user's email address.
  /// - The ``inviteUserByEmail(_:data:redirectTo:)`` method is typically used by administrators to invite users to join the application.
  /// - Parameters:
  ///   - email: The email address of the user.
  ///   - data: A custom data object to store additional metadata about the user. This maps to the `auth.users.user_metadata` column.
  ///   - redirectTo: The URL which will be appended to the email link sent to the user's email address. Once clicked the user will end up on this URL.
  /// - Note: that PKCE is not supported when using ``inviteUserByEmail(_:data:redirectTo:)``. This is because the browser initiating the invite is often different from the browser accepting the invite which makes it difficult to provide the security guarantees required of the PKCE flow.
  @discardableResult
  public func inviteUserByEmail(
    _ email: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil
  ) async throws -> User {
    try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/invite"),
        method: .post,
        query: [
          (redirectTo ?? configuration.redirectToURL).map {
            URLQueryItem(
              name: "redirect_to",
              value: $0.absoluteString
            )
          }
        ].compactMap { $0 },
        body: encoder.encode(
          [
            "email": .string(email),
            "data": data.map({ AnyJSON.object($0) }) ?? .null,
          ]
        )
      )
    )
    .decoded(decoder: configuration.decoder)
  }

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

  /// Get a list of users.
  ///
  /// This function should only be called on a server.
  ///
  /// - Warning: Never expose your `service_role` key in the client.
  public func listUsers(params: PageParams? = nil) async throws -> ListUsersPaginatedResponse {
    struct Response: Decodable {
      let users: [User]
      let aud: String
    }

    let httpResponse = try await api.execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/users"),
        method: .get,
        query: [
          URLQueryItem(name: "page", value: params?.page?.description ?? ""),
          URLQueryItem(name: "per_page", value: params?.perPage?.description ?? ""),
        ]
      )
    )

    let response = try httpResponse.decoded(as: Response.self, decoder: configuration.decoder)

    var pagination = ListUsersPaginatedResponse(
      users: response.users,
      aud: response.aud,
      lastPage: 0,
      total: httpResponse.headers[.xTotalCount].flatMap(Int.init) ?? 0
    )

    let links = httpResponse.headers[.link]?.components(separatedBy: ",") ?? []
    if !links.isEmpty {
      for link in links {
        let page = link.components(separatedBy: ";")[0].components(separatedBy: "=")[1].prefix(
          while: \.isNumber)
        let rel = link.components(separatedBy: ";")[1].components(separatedBy: "=")[1]

        if rel == "\"last\"", let lastPage = Int(page) {
          pagination.lastPage = lastPage
        } else if rel == "\"next\"", let nextPage = Int(page) {
          pagination.nextPage = nextPage
        }
      }
    }

    return pagination
  }

  public func generateLink() {
    
  }
}

extension HTTPField.Name {
  static let xTotalCount = Self("x-total-count")!
  static let link = Self("link")!
}
