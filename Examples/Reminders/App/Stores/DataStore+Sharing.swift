import Foundation

// List sharing. None of these writes is optimistic: each one changes what the user can
// read, so the app waits for the server.
extension DataStore {
  func isShared(_ list: ReminderList) -> Bool {
    !isOwner(of: list) || members.contains { $0.listID == list.id }
  }

  func profile(id: UUID) -> Profile? {
    profiles.first { $0.id == id }
  }

  /// The members of a list. The owner is not in this array.
  func members(of listID: UUID) -> [ListMember] {
    members.filter { $0.listID == listID }
  }

  func pendingInvitations(for listID: UUID) -> [Invitation] {
    sentInvitations.filter { $0.listID == listID && $0.status == "pending" }
  }

  func invite(email: String, listID: UUID) async throws {
    let invitation = try await sharingRepository.invite(email: email, listID: listID)
    // A new invitation replaces an answered one for the same person.
    changeCount += 1
    sentInvitations.removeAll {
      $0.listID == listID && $0.invitedEmail == invitation.invitedEmail
    }
    sentInvitations.append(invitation)
  }

  func revokeInvitation(id: UUID) async throws {
    try await sharingRepository.revoke(invitationID: id)
    changeCount += 1
    sentInvitations.removeAll { $0.id == id }
  }

  func accept(invitationID: UUID) async throws {
    try await sharingRepository.accept(invitationID: invitationID)
    changeCount += 1
    incomingInvitations.removeAll { $0.id == invitationID }
    // The user can now read a new list, its reminders and the people in it.
    try await load()
  }

  func decline(invitationID: UUID) async throws {
    try await sharingRepository.decline(invitationID: invitationID)
    changeCount += 1
    incomingInvitations.removeAll { $0.id == invitationID }
  }

  func removeMember(userID: UUID, listID: UUID) async throws {
    try await sharingRepository.removeMember(userID: userID, listID: listID)
    changeCount += 1
    members.removeAll { $0.listID == listID && $0.userID == userID }
  }

  func leaveList(id: UUID) async throws {
    try await sharingRepository.removeMember(userID: userID, listID: id)
    removeList(id: id)
    changeCount += 1
    members.removeAll { $0.listID == id }
  }

  /// Reads the invitations again. Realtime calls it for each change of the table.
  func reloadInvitations() async throws {
    async let sent = sharingRepository.fetchSentInvitations(ownerID: userID)
    async let incoming = sharingRepository.fetchIncoming()
    (sentInvitations, incomingInvitations) = try await (sent, incoming)
  }
}
