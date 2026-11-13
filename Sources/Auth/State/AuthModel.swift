#if canImport(Observation)
  import ConcurrencyExtras
  public import Observation

  /// An observable mirror of an ``AuthClient``'s ``AuthStatus``, for SwiftUI and other
  /// Observation-based UI.
  ///
  /// Create one model for the app and read its properties in a view body. SwiftUI re-renders the
  /// view when a property it read changes.
  ///
  /// ```swift
  /// @State private var auth = AuthModel(client: supabase.auth)
  ///
  /// var body: some View {
  ///   switch auth.status {
  ///   case .loading: ProgressView()
  ///   case .signedIn: HomeView()
  ///   case .signedOut: SignInView()
  ///   }
  /// }
  /// ```
  ///
  /// The model subscribes to ``AuthClient/events()`` when you create it. It stops when the model is
  /// released. Apps that support iOS 16 or earlier consume ``AuthClient/events()`` in `.task`
  /// instead.
  ///
  /// The model keeps the status of each ``AuthChange`` and drops its ``AuthChange/event``. A change
  /// that leaves the status as it was does nothing. To react to an event such as
  /// ``AuthChangeEvent/passwordRecovery``, consume ``AuthClient/events()`` as well.
  ///
  /// The model updates on the main actor after the client has changed. Right after an `await` on a
  /// sign-in, read ``AuthClient/status`` for the state the client holds now.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
  @MainActor @Observable
  public final class AuthModel {
    /// Whether a user is signed in.
    ///
    /// It starts as the client's current ``AuthClient/status``, then follows every
    /// ``AuthChange``, starting with ``AuthChangeEvent/initialSession``.
    public private(set) var status: AuthStatus

    /// The current session, or `nil` when no user is signed in. The session may be expired; check
    /// ``Session/isExpired(at:leeway:)``.
    public var session: Session? { status.session }

    /// The signed-in user, or `nil` when no user is signed in.
    public var user: User? { session?.user }

    /// Whether ``status`` is ``AuthStatus/loading``. This version of the client never reports that
    /// status, so the value is always `false`.
    public var isLoading: Bool { status == .loading }

    // A Sendable box, so the nonisolated deinit can cancel the task.
    @ObservationIgnored private let task = LockIsolated<Task<Void, Never>?>(nil)

    /// Creates a model that follows `client`.
    ///
    /// - Parameter client: The client whose ``AuthClient/events()`` the model consumes.
    public init(client: AuthClient) {
      status = client.status
      let changes = client.events()
      task.setValue(
        Task { @MainActor [weak self] in
          for await change in changes {
            guard let self else { return }
            // Observation invalidates readers on every write, equal value or not.
            if status != change.status { status = change.status }
          }
        })
    }

    deinit {
      task.value?.cancel()
    }
  }
#endif
