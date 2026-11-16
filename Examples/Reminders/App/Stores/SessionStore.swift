import Observation
import Supabase

/// The signed-in user. It follows `auth.authStateChanges`, the one source of truth for
/// the session.
@MainActor
@Observable
final class SessionStore {
  private(set) var user: User?
  /// True until the first auth event arrives. The UI shows a spinner while it is true.
  private(set) var isLoading = true

  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  /// Runs until the task is cancelled. Call it from a `.task` modifier.
  func observe() async {
    for await (event, session) in client.auth.authStateChanges {
      switch event {
      case .initialSession:
        // The stored session comes first, and it can be expired. The client then
        // refreshes it and sends `tokenRefreshed`, or `signedOut` if that fails.
        user = session.flatMap { $0.isExpired ? nil : $0.user }
        isLoading = session?.isExpired ?? false
      case .signedIn, .tokenRefreshed, .userUpdated:
        user = session?.user
        isLoading = false
      case .signedOut:
        user = nil
        isLoading = false
      default:
        break
      }
    }
  }

  func signIn(email: String, password: String) async throws {
    try await client.auth.signIn(email: email, password: password)
  }

  func signUp(email: String, password: String) async throws {
    try await client.auth.signUp(email: email, password: password)
  }

  func signOut() async throws {
    try await client.auth.signOut()
  }
}
