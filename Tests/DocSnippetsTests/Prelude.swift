import Foundation
import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Stand-ins for the app's own names that the documentation snippets use. The snippets are in
// the generated files next to this one; see scripts/check-doc-snippets.sh.

struct MyCustomAuthStorage: AuthStorage {
  func load(key: String) async throws -> Data? { nil }
  func save(_ data: Data, key: String) async throws {}
  func remove(key: String) async throws {}
}

extension URLSession {
  static var myCustomSession: URLSession { .shared }
}
