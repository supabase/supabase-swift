import Foundation
import HTTPTypes
import OpenAPIURLSession

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public class StorageApi: @unchecked Sendable {
  public let configuration: StorageClientConfiguration

  private let client: Client

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    // if legacy uri is used, replace with new storage host (disables request buffering to allow > 50GB uploads)
    // "project-ref.supabase.co" becomes "project-ref.storage.supabase.co"
    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(configuration.url)")
      }

      let regex = try! NSRegularExpression(pattern: "supabase.(co|in|red)$")

      let isSupabaseHost =
        regex.firstMatch(in: host, range: NSRange(location: 0, length: host.utf16.count)) != nil

      if isSupabaseHost, !host.contains("storage.supabase.") {
        components.host = host.replacingOccurrences(of: "supabase.", with: "storage.supabase.")
      }

      configuration.url = components.url!
    }

    self.configuration = configuration

    client = Client(
      serverURL: configuration.url,
      transport: configuration.transport
        ?? FetchTransportAdapter(fetch: configuration.session.fetch),
      middlewares: [LoggingMiddleware(logger: .storage)]
    )
  }

  @discardableResult
  func execute(
    _ request: HTTPTypes.HTTPRequest,
    requestBody: HTTPBody? = nil
  ) async throws -> (response: HTTPTypes.HTTPResponse, responseBody: HTTPBody) {
    var request = request
    request.headerFields.merge(with: HTTPFields(configuration.headers))

    let (response, responseBody) = try await client.send(request, body: requestBody)

    guard response.status.kind == .successful else {
      let data = try await Data(collecting: responseBody, upTo: .max)
      if let error = try? configuration.decoder.decode(
        StorageError.self,
        from: data
      ) {
        throw error
      }

      throw HTTPError(
        data: data,
        response: HTTPURLResponse(
          httpResponse: response,
          url: request.url!
        )!
      )
    }

    return (response, responseBody)
  }
}
