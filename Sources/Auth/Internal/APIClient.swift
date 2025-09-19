import Alamofire
import Foundation

struct NoopParameter: Encodable, Sendable {}

extension AuthClient {

  private var defaultEncoder: any ParameterEncoder {
    JSONParameterEncoder(encoder: .auth)
  }

  func execute<RequestBody: Encodable & Sendable>(
    _ url: URL,
    method: HTTPMethod = .get,
    headers: HTTPHeaders = [:],
    query: Parameters? = nil,
    body: RequestBody? = NoopParameter(),
    encoder: (any ParameterEncoder)? = nil
  ) throws -> DataRequest {
    var request = try URLRequest(url: url, method: method, headers: headers)

    request = try URLEncoding.queryString.encode(request, with: query)
    if RequestBody.self != NoopParameter.self {
      request = try (encoder ?? defaultEncoder).encode(body, into: request)
    }

    return alamofireSession.request(request)
      .validate { _, response, data in
        guard 200..<300 ~= response.statusCode else {
          return .failure(self.handleError(response: response, data: data ?? Data()))
        }
        return .success(())
      }
  }

  nonisolated func handleError(response: HTTPURLResponse, data: Data) -> AuthError {
    guard
      let error = try? JSONDecoder.auth.decode(
        _RawAPIErrorResponse.self,
        from: data
      )
    else {
      return .api(
        message: "Unexpected error",
        errorCode: .unexpectedFailure,
        underlyingData: data,
        underlyingResponse: response
      )
    }

    let responseAPIVersion = parseResponseAPIVersion(response)

    let errorCode: ErrorCode? =
      if let responseAPIVersion, responseAPIVersion >= apiVersions[._20240101]!.timestamp,
        let code = error.code
      {
        ErrorCode(code)
      } else {
        error.errorCode
      }

    if errorCode == nil, let weakPassword = error.weakPassword {
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: weakPassword.reasons ?? []
      )
    } else if errorCode == .weakPassword {
      return .weakPassword(
        message: error._getErrorMessage(),
        reasons: error.weakPassword?.reasons ?? []
      )
    } else if errorCode == .sessionNotFound {
      return .sessionMissing
    } else {
      return .api(
        message: error._getErrorMessage(),
        errorCode: errorCode ?? .unknown,
        underlyingData: data,
        underlyingResponse: response
      )
    }
  }

  nonisolated private func parseResponseAPIVersion(_ response: HTTPURLResponse) -> Date? {
    guard let apiVersion = response.headers[apiVersionHeaderNameHeaderKey] else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: "\(apiVersion)T00:00:00.0Z")
  }
}

// Struct for mapping all fields possibly returned by API.
struct _RawAPIErrorResponse: Decodable {
  let msg: String?
  let message: String?
  let errorDescription: String?
  let error: String?
  let code: String?
  let errorCode: ErrorCode?
  let weakPassword: _WeakPassword?

  struct _WeakPassword: Decodable {
    let reasons: [String]?
  }

  func _getErrorMessage() -> String {
    msg ?? message ?? errorDescription ?? error ?? "Unknown"
  }
}
