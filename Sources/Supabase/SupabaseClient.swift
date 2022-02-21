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
  private var supabaseUrl: String
  private var supabaseKey: String
  private var schema: String
  private var restUrl: String
  private var realtimeUrl: String
  private var authUrl: String
  private var storageUrl: String

  /// Auth client for Supabase
  public var auth: GoTrueClient

  /// Storage client for Supabase.
  public var storage: SupabaseStorageClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return SupabaseStorageClient(url: storageUrl, headers: headers)
  }

  /// Database client for Supabase.
  public var database: PostgrestClient {
    var headers: [String: String] = defaultHeaders
    headers["Authorization"] = "Bearer \(auth.session?.accessToken ?? supabaseKey)"
    return PostgrestClient(url: restUrl, headers: headers, schema: schema)
  }

  /// Realtime client for Supabase
  public var realtime: RealtimeClient

  private var defaultHeaders: [String: String]

  /// Init `Supabase` with the provided parameters.
  /// - Parameters:
  ///   - supabaseUrl: Unique Supabase project url
  ///   - supabaseKey: Supabase anonymous API Key
  ///   - schema: Database schema name, defaults to `public`
  ///   - autoRefreshToken: Toggles whether `Supabase.auth` automatically refreshes auth tokens. Defaults to `true`
  public init(
    supabaseUrl: String,
    supabaseKey: String,
    schema: String = "public",
    autoRefreshToken: Bool = true
  ) {
    self.supabaseUrl = supabaseUrl
    self.supabaseKey = supabaseKey
    self.schema = schema
    restUrl = "\(supabaseUrl)/rest/v1"
    realtimeUrl = "\(supabaseUrl)/realtime/v1"
    authUrl = "\(supabaseUrl)/auth/v1"
    storageUrl = "\(supabaseUrl)/storage/v1"

    defaultHeaders = ["X-Client-Info": "supabase-swift/0.0.1", "apikey": supabaseKey]

    auth = GoTrueClient(
      url: authUrl,
      headers: defaultHeaders,
      autoRefreshToken: autoRefreshToken
    )
    realtime = RealtimeClient(endPoint: realtimeUrl, params: defaultHeaders)
  }
}
