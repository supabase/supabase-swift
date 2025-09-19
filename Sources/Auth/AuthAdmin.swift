//
//  AuthAdmin.swift
//
//
//  Created by Guilherme Souza on 25/01/24.
//

import Foundation

/// Administrative API for Supabase Auth.
///
/// The `AuthAdmin` struct provides administrative functionality for user management.
/// These methods require elevated permissions and should only be used on the server side
/// with the `service_role` key.
///
/// - Warning: These methods require `service_role` key and should never be exposed to client-side code.
///
/// ## Basic Usage
///
/// ```swift
/// // Get user by ID
/// let user = try await authClient.admin.getUserById(userId)
///
/// // Create a new user
/// let newUser = try await authClient.admin.createUser(
///   attributes: AdminUserAttributes(
///     email: "admin@example.com",
///     password: "securepassword",
///     emailConfirm: true
///   )
/// )
///
/// // Update user attributes
/// let updatedUser = try await authClient.admin.updateUser(
///   uid: userId,
///   attributes: AdminUserAttributes(
///     data: ["role": "admin"]
///   )
/// )
/// ```
///
/// ## User Management
///
/// ```swift
/// // List users with pagination
/// let users = try await authClient.admin.listUsers(
///   params: AdminListUsersParams(
///     page: 1,
///     perPage: 50
///   )
/// )
///
/// // Delete a user
/// try await authClient.admin.deleteUser(id: userId)
///
/// // Invite a user
/// let invitedUser = try await authClient.admin.inviteUserByEmail(
///   email: "newuser@example.com",
///   redirectTo: URL(string: "myapp://invite")
/// )
/// ```
///
/// ## Link Generation
///
/// ```swift
/// // Generate a magic link
/// let link = try await authClient.admin.generateLink(
///   params: GenerateLinkParams(
///     type: .magicLink,
///     email: "user@example.com",
///     redirectTo: URL(string: "myapp://auth/callback")
///   )
/// )
/// ```
public struct AuthAdmin: Sendable {
  let client: AuthClient

  /// Get user by id.
  /// - Parameter uid: The user's unique identifier.
  /// - Note: This function should only be called on a server. Never expose your `service_role` key in the browser.
  public func getUserById(_ uid: UUID) async throws(AuthError) -> User {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("admin/users/\(uid)")
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Updates the user data.
  /// - Parameters:
  ///   - uid: The user id you want to update.
  ///   - attributes: The data you want to update.
  @discardableResult
  public func updateUserById(_ uid: UUID, attributes: AdminUserAttributes) async throws(AuthError)
    -> User
  {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("admin/users/\(uid)"),
        method: .put,
        body: attributes
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Creates a new user.
  ///
  /// - To confirm the user's email address or phone number, set ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` to `true`. Both arguments default to `false`.
  /// - ``createUser(attributes:)`` will not send a confirmation email to the user. You can use ``inviteUserByEmail(_:data:redirectTo:)`` if you want to send them an email invite instead.
  /// - If you are sure that the created user's email or phone number is legitimate and verified, you can set the ``AdminUserAttributes/emailConfirm`` or ``AdminUserAttributes/phoneConfirm`` param to true.
  /// - Warning: Never expose your `service_role` key on the client.
  @discardableResult
  public func createUser(attributes: AdminUserAttributes) async throws(AuthError) -> User {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("admin/users"),
        method: .post,
        body: attributes
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value
    }
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
  ) async throws(AuthError) -> User {
    try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("admin/invite"),
        method: .post,
        query: (redirectTo ?? self.client.configuration.redirectToURL).map {
          ["redirect_to": $0.absoluteString]
        },
        body: [
          "email": .string(email),
          "data": data.map({ AnyJSON.object($0) }) ?? .null,
        ]
      )
      .serializingDecodable(User.self, decoder: JSONDecoder.auth)
      .value
    }
  }

  /// Delete a user. Requires `service_role` key.
  /// - Parameter id: The id of the user you want to delete.
  /// - Parameter shouldSoftDelete: If true, then the user will be soft-deleted (setting
  /// `deleted_at` to the current timestamp and disabling their account while preserving their data)
  /// from the auth schema.
  ///
  /// - Warning: Never expose your `service_role` key on the client.
  public func deleteUser(id: UUID, shouldSoftDelete: Bool = false) async throws(AuthError) {
    _ = try await wrappingError(or: mapToAuthError) {
      try await self.client.execute(
        self.client.url.appendingPathComponent("admin/users/\(id)"),
        method: .delete,
        body: DeleteUserRequest(shouldSoftDelete: shouldSoftDelete)
      ).serializingData().value
    }
  }

  /// Get a list of users.
  ///
  /// This function should only be called on a server.
  ///
  /// - Warning: Never expose your `service_role` key in the client.
  public func listUsers(
    params: PageParams? = nil
  ) async throws(AuthError) -> ListUsersPaginatedResponse {
    struct Response: Decodable {
      let users: [User]
      let aud: String
    }

    return try await wrappingError(or: mapToAuthError) {
      let httpResponse = try await self.client.execute(
        self.client.url.appendingPathComponent("admin/users"),
        query: [
          "page": params?.page?.description ?? "",
          "per_page": params?.perPage?.description ?? "",
        ]
      )
      .serializingDecodable(Response.self, decoder: JSONDecoder.auth)
      .response

      let response = try httpResponse.result.get()

      var pagination = ListUsersPaginatedResponse(
        users: response.users,
        aud: response.aud,
        lastPage: 0,
        total: httpResponse.response?.headers["X-Total-Count"].flatMap(Int.init) ?? 0
      )

      let links =
        httpResponse.response?.headers["Link"].flatMap { $0.components(separatedBy: ",") } ?? []
      if !links.isEmpty {
        for link in links {
          let page = link.components(separatedBy: ";")[0].components(separatedBy: "=")[1].prefix(
            while: \.isNumber
          )
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

  /*
   Generate link is commented out temporarily due issues with they Auth's decoding is configured.
   Will revisit it later.
  
  /// Generates email links and OTPs to be sent via a custom email provider.
  ///
  /// - Parameter params: The parameters for the link generation.
  /// - Throws: An error if the link generation fails.
  /// - Returns: The generated link.
  public func generateLink(params: GenerateLinkParams) async throws -> GenerateLinkResponse {
    try await execute(
      HTTPRequest(
        url: configuration.url.appendingPathComponent("admin/generate_link").appendingQueryItems(
          [
            (params.redirectTo ?? configuration.redirectToURL).map {
              URLQueryItem(
                name: "redirect_to",
                value: $0.absoluteString
              )
            }
          ].compactMap { $0 }
        ),
        method: .post,
        body: encoder.encode(params.body)
      )
    ).decoded(decoder: configuration.decoder)
  }
   */
}
