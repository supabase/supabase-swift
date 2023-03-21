import Foundation
import GoTrue

public struct SupabaseClientOptions {
  public let db: DatabaseOptions
  public let auth: AuthOptions
  public let global: GlobalOptions

  public struct DatabaseOptions {
    /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
    /// Supabase. Defaults to `public`.
    public let schema: String

    public init(schema: String = "public") {
      self.schema = schema
    }
  }

  public struct AuthOptions {
    /// Optional key name used for storing tokens in local storage.
    public let storageKey: String?

    /// A storage provider. Used to store the logged-in session.
    public let storage: GoTrueLocalStorage?

    public init(storageKey: String? = nil, storage: GoTrueLocalStorage? = nil) {
      self.storageKey = storageKey
      self.storage = storage
    }
  }

  public struct GlobalOptions {
    public let headers: [String: String]
    public let httpClient: SupabaseClient.HTTPClient

    public init(headers: [String: String] = [:], httpClient: SupabaseClient.HTTPClient = .init()) {
      self.headers = headers
      self.httpClient = httpClient
    }
  }

  public init(
    db: DatabaseOptions = .init(),
    auth: AuthOptions = .init(),
    global: GlobalOptions = .init()
  ) {
    self.db = db
    self.auth = auth
    self.global = global
  }
}
