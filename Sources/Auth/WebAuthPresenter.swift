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
}

/// A presenter that runs a closure.
///
/// ```swift
/// try await supabase.auth.signInWithOAuth(
///   .github,
///   presenter: ClosurePresenter { url, callbackScheme in
///     try await webAuthenticationSession.authenticate(
///       using: url,
///       callbackURLScheme: callbackScheme ?? "myapp"
///     )
///   }
/// )
/// ```
public struct ClosurePresenter: WebAuthPresenter {
  private let _authenticate:
    @MainActor @Sendable (_ url: URL, _ callbackScheme: String?) async throws -> URL

  /// Creates a presenter that runs `authenticate`.
  ///
  /// - Parameter authenticate: Opens the URL and returns the callback URL. It gets the same
  ///   arguments as ``authenticate(url:callbackScheme:)``.
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
