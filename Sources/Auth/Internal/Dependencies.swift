import ConcurrencyExtras
import Foundation

struct Dependencies: Sendable {
  var configuration: AuthClient.Configuration
  var http: any HTTPClientType
  var api: APIClient
  var codeVerifierStorage: CodeVerifierStorage
  var sessionStorage: SessionStorage
  var sessionManager: SessionManager

  var eventEmitter = AuthStateChangeEventEmitter()
  var date: @Sendable () -> Date = { Date() }

  var urlOpener: URLOpener = .live
  var pkce: PKCE = .live
  var logger: (any SupabaseLogger)?

  var resolvedEncoder: JSONEncoder { configuration.resolvedEncoder }
  var resolvedDecoder: JSONDecoder { configuration.resolvedDecoder }
}

/// Per-`AuthClient` dependency box.
///
/// A reference type on purpose: it is created *empty*, handed to every collaborator while
/// `AuthClient.init` closes the circular graph, and only filled in once that graph is complete.
/// Collaborators resolve fields lazily via `dependencies.value.x`.
///
/// The graph this holds is self-referential (`DependenciesContainer` → `Dependencies` →
/// `APIClient`/`SessionManager`/storage closures → `DependenciesContainer`), so an `AuthClient`
/// and its container leak together for the process lifetime rather than deallocating — this
/// matches today's behavior, where the equivalent global registry entry is never removed either.
/// Breaking that cycle deterministically requires cancelling owned background work (e.g. the
/// auto-refresh task) first; that's tracked separately and out of scope for this refactor.
final class DependenciesContainer: Sendable {
  private let storage = LockIsolated<Dependencies?>(nil)

  /// Installs the fully built graph. Called exactly once, at the end of `AuthClient.init`.
  func bootstrap(_ dependencies: Dependencies) {
    storage.withValue {
      precondition($0 == nil, "DependenciesContainer bootstrapped more than once.")
      $0 = dependencies
    }
  }

  var value: Dependencies {
    guard let value = storage.value else {
      fatalError(
        "Auth dependencies accessed before AuthClient.init completed, or after the AuthClient was deallocated."
      )
    }
    return value
  }

  /// In-place mutation, used by tests to swap `date` / `pkce` / `urlOpener` post-init.
  func withValue<T: Sendable>(_ body: @Sendable (inout Dependencies) throws -> T) rethrows -> T {
    try storage.withValue { deps in
      guard deps != nil else { fatalError("Auth dependencies not bootstrapped.") }
      return try body(&deps!)
    }
  }
}
