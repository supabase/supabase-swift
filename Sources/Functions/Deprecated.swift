import Foundation

extension FunctionsClient {
    @available(
        *, deprecated,
        message:
            "Use init(url:headers:region:logger:alamofireSession:) instead. This initializer will be removed in a future version."
    )
    @_disfavoredOverload
    public convenience init(
        url: URL,
        headers: [String: String] = [:],
        region: String? = nil,
        logger: (any SupabaseLogger)? = nil,
        fetch: @escaping FetchHandler
    ) {
        self.init(
            url: url,
            headers: headers,
            region: region,
            logger: logger,
            fetch: fetch,
            alamofireSession: .default
        )
    }

    @available(
        *, deprecated,
        message:
            "Use init(url:headers:region:logger:alamofireSession:) instead. This initializer will be removed in a future version."
    )
    public convenience init(
        url: URL,
        headers: [String: String] = [:],
        region: FunctionRegion? = nil,
        logger: (any SupabaseLogger)? = nil,
        fetch: @escaping FetchHandler
    ) {
        self.init(
            url: url, headers: headers, region: region?.rawValue, logger: logger, fetch: fetch,
            alamofireSession: .default)
    }
}
