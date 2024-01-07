import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLResponse {
    // Windows and Linux don't have the ability to empty initialize a URLResponse like `URLReponse()` so
    // We provide a function that can give us the right value on an platform.
    public static func empty() -> URLResponse {
        #if os(Windows) || os(Linux)
        URLResponse(url: .init(string: "https://supabase.com")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #else
        URLResponse()
        #endif
    }
}

