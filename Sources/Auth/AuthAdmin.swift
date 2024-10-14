//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

import Foundation
import Helpers
import HTTPTypes

public struct AuthAdmin: Sendable {
  let clientID: AuthClientID

  var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }
  var api: APIClient { Dependencies[clientID].api }
  var encoder: JSONEncoder { Dependencies[clientID].encoder }

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
        let page = link.components(separatedBy: ";")[0].components(separatedBy: "=")[1].prefix(while: \.isNumber)
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
}

extension HTTPField.Name {
  static let xTotalCount = Self("x-total-count")!
  static let link = Self("link")!
}
