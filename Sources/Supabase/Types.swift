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
    /// A storage provider. Used to store the logged-in session.
    public let storage: GoTrueLocalStorage?

    public init(storage: GoTrueLocalStorage? = nil) {
      self.storage = storage
    }
  }

  public struct GlobalOptions {
    public let headers: [String: String]
    public let session: URLSession

    public init(headers: [String: String] = [:], session: URLSession = .shared) {
      self.headers = headers
      self.session = session
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
