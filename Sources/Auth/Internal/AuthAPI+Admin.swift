//
//  AuthAPI+Admin.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes

extension HTTPField.Name {
  static let xTotalCount = Self("x-total-count")!
  static let link = Self("link")!
}

// MARK: - Users

extension AuthAPI {
  func adminUser(id: UUID) -> AuthRequest<User> {
    request(.get, "admin/users/\(id)", decode: decoding(User.self))
  }

  func adminUpdateUser(
    id: UUID,
    attributes: AdminUserAttributes
  ) throws -> AuthRequest<User> {
    try request(
      .put, "admin/users/\(id)", body: encoder.encode(attributes), decode: decoding(User.self))
  }

  func adminCreateUser(attributes: AdminUserAttributes) throws -> AuthRequest<User> {
    try request(
      .post, "admin/users", body: encoder.encode(attributes), decode: decoding(User.self))
  }

  func adminInviteUser(
    email: String,
    data: [String: JSONValue]?,
    redirectTo: URL?
  ) throws -> AuthRequest<User> {
    try request(
      .post, "invite", query: redirectQuery(redirectTo),
      body: encoder.encode(
        [
          "email": .string(email),
          "data": data.map({ JSONValue.object($0) }) ?? .null,
        ]
      ),
      decode: decoding(User.self)
    )
  }

  func adminDeleteUser(id: UUID, shouldSoftDelete: Bool) throws -> AuthRequest<Void> {
    try request(
      .delete, "admin/users/\(id)",
      body: encoder.encode(DeleteUserRequest(shouldSoftDelete: shouldSoftDelete)),
      decode: ignoringBody)
  }

  func adminListUsers(params: PageParams?) -> AuthRequest<ListUsersPaginatedResponse> {
    struct Response: Decodable {
      let users: [User]
      let aud: String
    }

    return request(
      .get, "admin/users", query: pageQuery(params),
      decode: { [decoder] httpResponse, data in
        let response = try data.decoded(as: Response.self, decoder: decoder)
        let pages = Self.pages(httpResponse)

        return ListUsersPaginatedResponse(
          users: response.users,
          audience: response.aud,
          nextPage: pages.next,
          lastPage: pages.last ?? 0,
          total: pages.total
        )
      }
    )
  }

  func adminGenerateLink(params: GenerateLinkParams) throws -> AuthRequest<GenerateLinkResponse> {
    try request(
      .post, "admin/generate_link", query: redirectQuery(params.redirectTo),
      body: encoder.encode(params.body), decode: decoding(GenerateLinkResponse.self))
  }

  private func pageQuery(_ params: PageParams?) -> [URLQueryItem] {
    [
      params?.page.map { URLQueryItem(name: "page", value: $0.description) },
      params?.perPage.map { URLQueryItem(name: "per_page", value: $0.description) },
    ].compactMap { $0 }
  }

  /// The pagination GoTrue reports in the `X-Total-Count` and `Link` headers.
  private static func pages(_ response: HTTPResponse) -> (total: Int, last: Int?, next: Int?) {
    let links = parsePaginationLinks(response.headerFields[.link])
    return (
      total: response.headerFields[.xTotalCount].flatMap(Int.init) ?? 0,
      last: links["last"],
      next: links["next"]
    )
  }
}

// MARK: - Factors and passkeys

extension AuthAPI {
  func adminListFactors(userId: UUID) -> AuthRequest<[Factor]> {
    request(.get, "admin/users/\(userId)/factors", decode: decoding([Factor].self))
  }

  func adminDeleteFactor(id: UUID, userId: UUID) -> AuthRequest<Void> {
    request(.delete, "admin/users/\(userId)/factors/\(id)", decode: ignoringBody)
  }

  func adminListPasskeys(userId: UUID) -> AuthRequest<[PasskeyListItem]> {
    request(.get, "admin/users/\(userId)/passkeys", decode: decoding([PasskeyListItem].self))
  }

  func adminDeletePasskey(id: UUID, userId: UUID) -> AuthRequest<Void> {
    request(.delete, "admin/users/\(userId)/passkeys/\(id)", decode: ignoringBody)
  }
}

// MARK: - OAuth clients

extension AuthAPI {
  func adminListOAuthClients(
    params: PageParams?
  ) -> AuthRequest<ListOAuthClientsPaginatedResponse> {
    struct Response: Decodable {
      let clients: [OAuthClient]
      let aud: String
    }

    return request(
      .get, "admin/oauth/clients", query: pageQuery(params),
      decode: { [decoder] httpResponse, data in
        let response = try data.decoded(as: Response.self, decoder: decoder)
        let pages = Self.pages(httpResponse)

        return ListOAuthClientsPaginatedResponse(
          clients: response.clients,
          audience: response.aud,
          nextPage: pages.next,
          lastPage: pages.last ?? 0,
          total: pages.total
        )
      }
    )
  }

  func adminCreateOAuthClient(
    params: CreateOAuthClientParams
  ) throws -> AuthRequest<OAuthClient> {
    try request(
      .post, "admin/oauth/clients", body: encoder.encode(params),
      decode: decoding(OAuthClient.self))
  }

  func adminOAuthClient(id: UUID) -> AuthRequest<OAuthClient> {
    request(.get, "admin/oauth/clients/\(id)", decode: decoding(OAuthClient.self))
  }

  func adminUpdateOAuthClient(
    id: UUID,
    params: UpdateOAuthClientParams
  ) throws -> AuthRequest<OAuthClient> {
    try request(
      .put, "admin/oauth/clients/\(id)", body: encoder.encode(params),
      decode: decoding(OAuthClient.self))
  }

  func adminDeleteOAuthClient(id: UUID) -> AuthRequest<Void> {
    request(.delete, "admin/oauth/clients/\(id)", decode: ignoringBody)
  }

  func adminRegenerateOAuthClientSecret(id: UUID) -> AuthRequest<OAuthClient> {
    request(
      .post, "admin/oauth/clients/\(id)/regenerate_secret", decode: decoding(OAuthClient.self))
  }
}
