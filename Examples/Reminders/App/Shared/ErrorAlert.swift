import Supabase
import SwiftUI

extension View {
  /// Shows an alert while `error` has a value, and clears it on dismiss.
  func errorAlert(_ error: Binding<(any Error)?>) -> some View {
    alert(
      "Something went wrong",
      isPresented: Binding(
        get: { error.wrappedValue != nil },
        set: { if !$0 { error.wrappedValue = nil } }
      ),
      presenting: error.wrappedValue
    ) { _ in
      Button("OK", role: .cancel) {}
        .accessibilityIdentifier("error.ok")
    } message: { error in
      Text(errorMessage(for: error))
    }
  }
}

/// The text that the app shows for an error.
///
/// The database reports sharing rules with an error code or a fixed message. This
/// function turns them into sentences for the user.
func errorMessage(for error: any Error) -> String {
  guard let error = error as? PostgrestError else { return error.localizedDescription }
  if error.message.contains("cannot_invite_self") { return "You cannot invite yourself." }
  if error.message.contains("already_member") { return "This person is already a member." }
  if error.message.contains("invitation_not_found") {
    return "This invitation is no longer available."
  }
  // The only unique rule that a user can break is one pending invitation for each list
  // and email.
  if error.code == .uniqueViolation { return "This person already has an invitation." }
  return error.localizedDescription
}
