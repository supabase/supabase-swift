import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Bridges the generated OpenAPI client's HTTP layer onto ``StorageApi``'s existing
/// `execute(_:)` pipeline, so header merging, ``StorageError`` decoding, and the injectable
/// ``StorageHTTPSession`` all keep working unchanged for OpenAPI-routed requests.
struct StorageOpenAPITransport: ClientTransport {
  var execute: @Sendable (Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse

  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: OpenAPIRuntime.HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
    let requestTarget = request.path ?? ""
    let pathAndQuery = requestTarget.split(separator: "?", maxSplits: 1)
    let path = String(pathAndQuery.first ?? "")
    let query = pathAndQuery.count > 1 ? String(pathAndQuery[1]) : nil

    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw StorageOpenAPITransportError.invalidBaseURL(baseURL)
    }
    components.percentEncodedPath += path
    components.percentEncodedQuery = query

    guard let url = components.url else {
      throw StorageOpenAPITransportError.invalidRequestURL(path: requestTarget, baseURL: baseURL)
    }

    let requestBody: Data?
    if let body {
      requestBody = try await Data(collecting: body, upTo: .max)
    } else {
      requestBody = nil
    }

    var headers = HTTPFields()
    for field in request.headerFields {
      // ponytail: the generated client always sets an `Accept` header via
      // `converter.setAcceptHeader`; the hand-written implementations being migrated never sent
      // one, so drop it here to keep wire behavior byte-identical during the migration.
      if field.name == .accept { continue }
      if field.name == .contentType, field.value == "application/json; charset=utf-8" {
        // ponytail: the generated client always appends `; charset=utf-8` to JSON content types
        // via `converter.setRequiredRequestBodyAsJSON`; the hand-written implementations being
        // migrated always sent plain `application/json`, so strip the suffix here to keep wire
        // behavior byte-identical during the migration.
        headers[field.name] = "application/json"
        continue
      }
      headers[field.name] = field.value
    }

    let helpersRequest = Helpers.HTTPRequest(
      url: url,
      method: request.method,
      headers: headers,
      body: requestBody
    )

    let response = try await execute(helpersRequest)

    let responseBody: OpenAPIRuntime.HTTPBody? =
      response.data.isEmpty ? nil : OpenAPIRuntime.HTTPBody(response.data)

    return (
      HTTPTypes.HTTPResponse(status: .init(code: response.statusCode)),
      responseBody
    )
  }
}

enum StorageOpenAPITransportError: Error {
  case invalidBaseURL(URL)
  case invalidRequestURL(path: String, baseURL: URL)
}
