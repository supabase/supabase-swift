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
      .put, "admin/users/\(id)", body: encodeBody(attributes), decode: decoding(User.self))
  }

  func adminCreateUser(attributes: AdminUserAttributes) throws -> AuthRequest<User> {
    try request(
      .post, "admin/users", body: encodeBody(attributes), decode: decoding(User.self))
  }

  func adminInviteUser(
    email: String,
    userMetadata: JSONObject,
    redirectTo: URL?
  ) throws -> AuthRequest<User> {
    try request(
      .post, "invite", query: redirectQuery(redirectTo),
      body: encodeBody(["email": .string(email), "data": .object(userMetadata)] as JSONObject),
      decode: decoding(User.self)
    )
  }

  func adminDeleteUser(id: UUID, softDelete: Bool) throws -> AuthRequest<Void> {
    try request(
      .delete, "admin/users/\(id)",
      body: encodeBody(DeleteUserRequest(shouldSoftDelete: softDelete)),
      decode: ignoringBody)
  }

  func adminListUsers(page: Int?, pageSize: Int?) -> AuthRequest<UserPage> {
    struct Response: Decodable {
      let users: [User]
      let aud: String
    }

    return request(
      .get, "admin/users", query: pageQuery(page: page, pageSize: pageSize),
      decode: { [decoder] httpResponse, data in
        let response = try data.decoded(as: Response.self, decoder: decoder)
        let pages = Self.pages(httpResponse)

        return UserPage(
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
      body: encodeBody(params.body), decode: decoding(GenerateLinkResponse.self))
  }

  private func pageQuery(page: Int?, pageSize: Int?) -> [URLQueryItem] {
    [
      page.map { URLQueryItem(name: "page", value: $0.description) },
      pageSize.map { URLQueryItem(name: "per_page", value: $0.description) },
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
  func adminListFactors(userID: UUID) -> AuthRequest<[Factor]> {
    request(.get, "admin/users/\(userID)/factors", decode: decoding([Factor].self))
  }

  func adminDeleteFactor(id: UUID, userID: UUID) -> AuthRequest<Void> {
    request(.delete, "admin/users/\(userID)/factors/\(id)", decode: ignoringBody)
  }

  func adminListPasskeys(userID: UUID) -> AuthRequest<[PasskeyListItem]> {
    request(.get, "admin/users/\(userID)/passkeys", decode: decoding([PasskeyListItem].self))
  }

  func adminDeletePasskey(id: UUID, userID: UUID) -> AuthRequest<Void> {
    request(.delete, "admin/users/\(userID)/passkeys/\(id)", decode: ignoringBody)
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
      .get, "admin/oauth/clients", query: pageQuery(page: params?.page, pageSize: params?.perPage),
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
      .post, "admin/oauth/clients", body: encodeBody(params),
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
      .put, "admin/oauth/clients/\(id)", body: encodeBody(params),
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

// MARK: - Custom providers

extension AuthAPI {
  func adminListCustomProviders(type: CustomProviderType?) -> AuthRequest<[CustomProvider]> {
    struct Response: Decodable {
      let providers: [CustomProvider]?
    }

    return request(
      .get, "admin/custom-providers",
      query: type.map { [URLQueryItem(name: "type", value: $0.rawValue)] } ?? [],
      decode: { [decoder] _, data in
        try data.decoded(as: Response.self, decoder: decoder).providers ?? []
      }
    )
  }

  func adminCreateCustomProvider(
    params: CreateCustomProviderParams
  ) throws -> AuthRequest<CustomProvider> {
    try request(
      .post, "admin/custom-providers", body: encodeBody(params),
      decode: decoding(CustomProvider.self))
  }

  func adminCustomProvider(identifier: String) -> AuthRequest<CustomProvider> {
    request(
      .get, "admin/custom-providers/\(identifier)", decode: decoding(CustomProvider.self))
  }

  func adminUpdateCustomProvider(
    identifier: String,
    params: UpdateCustomProviderParams
  ) throws -> AuthRequest<CustomProvider> {
    try request(
      .put, "admin/custom-providers/\(identifier)", body: encodeBody(params),
      decode: decoding(CustomProvider.self))
  }

  func adminDeleteCustomProvider(identifier: String) -> AuthRequest<Void> {
    request(.delete, "admin/custom-providers/\(identifier)", decode: ignoringBody)
  }
}
