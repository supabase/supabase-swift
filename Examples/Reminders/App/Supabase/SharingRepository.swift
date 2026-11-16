import Foundation
import Supabase

/// All calls for list sharing: members, invitations and the profiles of other people.
struct SharingRepository: Sendable {
  let client: SupabaseClient

  /// The members of every list that the user can open. A list owner is not a member row.
  func fetchMembers() async throws -> [ListMember] {
    try await client.from("list_members").select().execute().value
  }

  /// The user's own profile and the profiles of people who share a list with the user.
  func fetchProfiles() async throws -> [Profile] {
    try await client.from("profiles").select().execute().value
  }

  /// The invitations of the lists that the user owns.
  func fetchSentInvitations(ownerID: UUID) async throws -> [Invitation] {
    try await client.from("list_invitations")
      .select()
      .eq("invited_by", value: ownerID)
      .order("created_at")
      .execute()
      .value
  }

  /// The pending invitations for the user's email.
  ///
  /// A database function returns them, because the user cannot read the list or the
  /// inviter's profile before acceptance.
  func fetchIncoming() async throws -> [IncomingInvitation] {
    try await client.rpc("my_invitations").execute().value
  }

  /// The database stores and compares emails in lower case.
  func invite(email: String, listID: UUID) async throws -> Invitation {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return try await client.from("list_invitations")
      .insert(["list_id": listID.uuidString, "invited_email": email])
      .select()
      .single()
      .execute()
      .value
  }

  func revoke(invitationID: UUID) async throws {
    try await client.from("list_invitations").delete().eq("id", value: invitationID).execute()
  }

  /// Adds the user to the list and marks the invitation as accepted, in one transaction.
  func accept(invitationID: UUID) async throws {
    try await client.rpc("accept_invitation", params: ["invitation_id": invitationID]).execute()
  }

  func decline(invitationID: UUID) async throws {
    try await client.rpc("decline_invitation", params: ["invitation_id": invitationID]).execute()
  }

  /// An owner removes a member, or a member leaves.
  func removeMember(userID: UUID, listID: UUID) async throws {
    try await client.from("list_members")
      .delete()
      .eq("list_id", value: listID)
      .eq("user_id", value: userID)
      .execute()
  }
}
