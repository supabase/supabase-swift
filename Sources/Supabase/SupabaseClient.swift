import Foundation
import GoTrue
import PostgREST
import Realtime
import SupabaseStorage

/// The main class for accessing Supabase functionality
///
/// Initialize this class using `.init(supabaseURL: String, supabaseKey: String)`
///
/// There are four main classes contained by the `Supabase` class.
/// 1.  `auth`
/// 2.  `database`
/// 3.  `realtime`
/// 4.  `storage`
/// Each class listed is available under `Supabase.{name}`, eg: `Supabase.auth`
///
/// For more usage information read the README.md
public class SupabaseClient {
  private var supabaseURL: URL
  private var supabaseKey: String
  private var schema: String
  private var restURL: URL
  private var realtimeURL: URL
  private var authURL: URL
  private var storageURL: URL

  /// Auth client for Supabase.
  public let auth: GoTrueClient

  /// Storage client for Supabase.
  public var storage: SupabaseStorageClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return SupabaseStorageClient(url: storageURL.absoluteString, headers: headers)
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return PostgrestClient(
      url: restURL.absoluteString,
      headers: headers,
      schema: schema,
      delegate: self
    )
  }

  /// Realtime client for Supabase
  public var realtime: RealtimeClient

  private var defaultHeaders: [String: String]

  /// Init `Supabase` with the provided parameters.
  /// - Parameters:
  ///   - supabaseURL: Unique Supabase project url
  ///   - supabaseKey: Supabase anonymous API Key
  ///   - schema: Database schema name, defaults to `public`
  ///   - autoRefreshToken: Toggles whether `Supabase.auth` automatically refreshes auth tokens. Defaults to `true`
  public init(
    supabaseURL: URL,
    supabaseKey: String,
    schema: String = "public",
    autoRefreshToken: Bool = true
  ) {
    self.supabaseURL = supabaseURL
    self.supabaseKey = supabaseKey
    self.schema = schema
    restURL = supabaseURL.appendingPathComponent("/rest/v1")
    realtimeURL = supabaseURL.appendingPathComponent("/realtime/v1")
    authURL = supabaseURL.appendingPathComponent("/auth/v1")
    storageURL = supabaseURL.appendingPathComponent("/storage/v1")

    defaultHeaders = [
      "X-Client-Info": "supabase-swift/\(version)",
      "apikey": supabaseKey,
    ]

    auth = GoTrueClient(
      url: authURL,
      headers: defaultHeaders
    )
    realtime = RealtimeClient(endPoint: realtimeURL.absoluteString, params: defaultHeaders)
  }
}

extension SupabaseClient: PostgrestClientDelegate {
  public func client(
    _ client: PostgrestClient,
    willSendRequest request: URLRequest,
    completion: @escaping (URLRequest) -> Void
  ) {
    Task {
      do {
        try await auth.refreshCurrentSessionIfNeeded()
        var request = request
        if let accessToken = auth.session?.accessToken {
          request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        completion(request)
      } catch {
        completion(request)
      }
    }
  }
}
