import Foundation

extension SupabaseClient {
  @available(
    *,
    deprecated,
    message: "Deprecated initializer, use init(supabaseURL:supabaseKey:options) instead."
  )
  public convenience init(
    supabaseURL: URL,
    supabaseKey: String,
    schema: String = "public",
    headers: [String: String] = [:],
    httpClient: HTTPClient = HTTPClient()
  ) {
    self.init(
      supabaseURL: supabaseURL,
      supabaseKey: supabaseKey,
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: schema),
        global: SupabaseClientOptions.GlobalOptions(
          headers: headers,
          httpClient: httpClient
        )
      )
    )
  }
}
