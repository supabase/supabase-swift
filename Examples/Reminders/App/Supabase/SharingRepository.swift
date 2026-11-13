import Foundation
@_spi(Experimental) import Supabase

/// All calls for list sharing: members, invitations and the profiles of other people.
struct SharingRepository: Sendable {
  let client: SupabaseClient

  /// The members of every list that the user can open. A list owner is not a member row.
  func fetchMembers() async throws -> [ListMember] {
    try await client.from(ListMember.self).select().execute().value
  }

  /// The user's own profile and the profiles of people who share a list with the user.
  func fetchProfiles() async throws -> [Profile] {
    try await client.from(Profile.self).select().execute().value
  }

  /// The invitations of the lists that the user owns.
  func fetchSentInvitations(ownerID: UUID) async throws -> [Invitation] {
    try await client.from(Invitation.self)
      .select()
      .where { $0.invitedBy.eq(ownerID) }
      .order { $0.createdAt.asc() }
      .execute()
      .value
  }

  /// The pending invitations for the user's email.
  ///
  /// A database function returns them, because the user cannot read the list or the
  /// inviter's profile before acceptance.
  func fetchIncoming() async throws -> [IncomingInvitation] {
    let rows = try await client.rpc.myInvitations().execute().value
    return rows.compactMap { row in
      guard let id = row.id, let listName = row.listName, let inviterName = row.inviterName
      else { return nil }
      return IncomingInvitation(id: id, listName: listName, inviterName: inviterName)
    }
  }

  /// The database stores and compares emails in lower case.
  func invite(email: String, listID: UUID) async throws -> Invitation {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return try await client.from(Invitation.self)
      .insert(Invitation.Draft(listID: listID, invitedEmail: email))
      .returning()
      .single()
      .execute()
      .value
  }

  func revoke(invitationID: UUID) async throws {
    try await client.from(Invitation.self).delete().where { $0.id.eq(invitationID) }.execute()
  }

  /// Adds the user to the list and marks the invitation as accepted, in one transaction.
  func accept(invitationID: UUID) async throws {
    try await client.rpc.acceptInvitation(invitationID: invitationID).execute()
  }

  func decline(invitationID: UUID) async throws {
    try await client.rpc.declineInvitation(invitationID: invitationID).execute()
  }

  /// An owner removes a member, or a member leaves.
  func removeMember(userID: UUID, listID: UUID) async throws {
    try await client.from(ListMember.self)
      .delete()
      .where { $0.listID.eq(listID) && $0.userID.eq(userID) }
      .execute()
  }
}
