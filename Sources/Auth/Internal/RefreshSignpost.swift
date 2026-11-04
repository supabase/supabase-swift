#if canImport(os)
  import os
#endif

/// An `OSSignposter` interval around one refresh request, so Instruments shows how long each
/// takes. Where `os` is missing, it only runs the refresh.
enum RefreshSignpost {
  #if canImport(os)
    private static let signposter = OSSignposter(subsystem: "io.supabase.auth", category: "refresh")
  #endif

  static func interval<Result>(
    _ refresh: () async throws -> Result
  ) async rethrows -> Result {
    #if canImport(os)
      let state = signposter.beginInterval("refresh", id: signposter.makeSignpostID())
      defer { signposter.endInterval("refresh", state) }
    #endif
    return try await refresh()
  }
}
