public import Foundation

/// Presents a provider's sign-in page and returns the URL it redirects to.
///
/// ``AuthClient/signInWithOAuth(_:options:presenter:)`` and
/// ``AuthClient/linkIdentity(_:options:presenter:)`` use a presenter to show the provider page.
/// On Apple platforms, the default presenter is ``ASWebAuthenticationSessionPresenter``. Use
/// ``ClosurePresenter`` to present the page another way.
public protocol WebAuthPresenter: Sendable {
  /// Opens `url` and returns the callback URL.
  ///
  /// - Parameters:
  ///   - url: The provider page to open.
  ///   - callbackScheme: The scheme of the redirect URL, or `nil` when the client has no
  ///     redirect URL.
  /// - Returns: The URL that the provider redirected to.
  /// - Throws: `CancellationError` when the user cancels.
  @MainActor func authenticate(url: URL, callbackScheme: String?) async throws -> URL

  /// Opens `url` and returns the callback URL, given the full redirect URL.
  ///
  /// The client calls this method. Implement it when the scheme is not enough, for example to
  /// listen for a universal link. The default implementation calls
  /// ``authenticate(url:callbackScheme:)`` with the scheme of `redirectURL`.
  ///
  /// - Parameters:
  ///   - url: The provider page to open.
  ///   - redirectURL: The redirect URL of the flow, or `nil` when the client has none.
  /// - Returns: The URL that the provider redirected to.
  /// - Throws: `CancellationError` when the user cancels.
  @MainActor func authenticate(url: URL, redirectURL: URL?) async throws -> URL
}

extension WebAuthPresenter {
  @MainActor
  public func authenticate(url: URL, redirectURL: URL?) async throws -> URL {
    try await authenticate(url: url, callbackScheme: redirectURL?.scheme)
  }
}

/// A presenter that runs a closure.
///
/// Use it to present the page another way. For example, an app that uses SwiftUI can pass the
/// `webAuthenticationSession` from the environment, which is available on iOS 16.4 and later:
///
/// ```swift
/// struct SignInView: View {
///   @Environment(\.webAuthenticationSession) private var webAuthenticationSession
///
///   var body: some View {
///     Button("Sign in with GitHub") {
///       Task {
///         try await supabase.auth.signInWithOAuth(
///           .github,
///           presenter: ClosurePresenter { [webAuthenticationSession] url, callbackScheme in
///             try await webAuthenticationSession.authenticate(
///               using: url,
///               callbackURLScheme: callbackScheme ?? "myapp"
///             )
///           }
///         )
///       }
///     }
///   }
/// }
/// ```
///
/// The closure gets the scheme of the redirect URL. To listen for a universal link, adopt
/// ``WebAuthPresenter/authenticate(url:redirectURL:)`` in your own presenter instead.
public struct ClosurePresenter: WebAuthPresenter {
  private let _authenticate:
    @MainActor @Sendable (_ url: URL, _ callbackScheme: String?) async throws -> URL

  /// Creates a presenter that runs `authenticate`.
  ///
  /// - Parameter authenticate: Opens the URL and returns the callback URL. It gets the same
  ///   arguments as ``ClosurePresenter/authenticate(url:callbackScheme:)``.
  public init(
    _ authenticate:
      @escaping @MainActor @Sendable (_ url: URL, _ callbackScheme: String?) async throws -> URL
  ) {
    _authenticate = authenticate
  }

  /// Runs the closure that this presenter holds.
  @MainActor
  public func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
    try await _authenticate(url, callbackScheme)
  }
}
