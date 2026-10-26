//
//  ErrorDecoder.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Maps a GoTrue response to the ``AuthError`` the caller sees.
///
/// The kind comes from the error code alone. GoTrue documents that `msg` text and the choice
/// between 400 and 422 are not stable, so neither is ever branched on.
enum ErrorDecoder {
  /// The error for a response to `request`, or `nil` when the status is 2xx.
  ///
  /// A 2xx response is never a server error: when its body does not decode, the caller's
  /// `Data.decoded(as:decoder:)` throws a `.decoding` error instead.
  static func error(response: HTTPResponse, data: Data, request: HTTPRequest) -> AuthError? {
    let status = response.status.code
    guard !(200..<300).contains(status) else { return nil }

    let errorResponse = HTTPErrorResponse(response, body: data)

    switch Body(response: response, data: data) {
    case .legacy(let coded), .versioned(let coded):
      return AuthError(
        kind: kindsByCode[coded.code, default: .server],
        message: coded.message ?? statusMessage(status),
        errorCode: coded.code,
        weakPasswordReasons: coded.weakPasswordReasons,
        response: errorResponse
      )

    case .oauth(let error, let description):
      let kind: AuthError.Kind =
        error == "invalid_grant" && isRefreshTokenGrant(request) ? .sessionInvalidated : .server
      return AuthError(
        kind: kind,
        message: description ?? error,
        oauthError: error,
        response: errorResponse
      )

    case .nonJSON:
      return AuthError(
        kind: .server,
        message: statusMessage(status),
        errorCode: .unexpectedFailure,
        response: errorResponse
      )
    }
  }

  /// Codes whose kind is not ``AuthError/Kind-swift.struct/server``.
  private static let kindsByCode: [ErrorCode: AuthError.Kind] = [
    .refreshTokenNotFound: .sessionInvalidated,
    .refreshTokenAlreadyUsed: .sessionInvalidated,
    .sessionExpired: .sessionInvalidated,
    .sessionNotFound: .sessionInvalidated,
    .userBanned: .sessionInvalidated,
    .flowStateNotFound: .oauthFlowFailed,
    .flowStateExpired: .oauthFlowFailed,
    .badCodeVerifier: .oauthFlowFailed,
  ]

  private static func statusMessage(_ status: Int) -> String {
    guard 500..<600 ~= status else {
      return "Unexpected response with status code \(status)."
    }
    let description = HTTPURLResponse.localizedString(forStatusCode: status)
    return description.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(description)"
  }

  private static func isRefreshTokenGrant(_ request: HTTPRequest) -> Bool {
    let queryItems = URLComponents(string: request.path ?? "")?.queryItems ?? []
    return queryItems.contains { $0.name == "grant_type" && $0.value == "refresh_token" }
  }
}

extension ErrorDecoder {
  /// The error body shapes GoTrue sends.
  private enum Body {
    /// `{"code": 400, "error_code": "invalid_credentials", "msg": "…"}`, for requests without
    /// `X-Supabase-Api-Version`.
    case legacy(Coded)
    /// `{"code": "invalid_credentials", "message": "…"}`, for API version 2024-01-01.
    case versioned(Coded)
    /// `{"error": "invalid_grant", "error_description": "…"}`, always HTTP 400 and without an
    /// error code. `error` may hold non-standard values with spaces, such as `invalid nonce`.
    case oauth(error: String, description: String?)
    /// Anything else, such as an HTML page from a proxy in front of GoTrue.
    case nonJSON

    struct Coded {
      var code: ErrorCode
      var message: String?
      var weakPasswordReasons: [String]
    }

    init(response: HTTPResponse, data: Data) {
      if let contentType = response.headerFields[.contentType],
        !contentType.lowercased().contains("json")
      {
        self = .nonJSON
        return
      }

      guard let raw = try? JSONDecoder().decode(RawBody.self, from: data) else {
        self = .nonJSON
        return
      }

      let reasons = raw.weakPassword?.reasons ?? []
      if let errorCode = raw.errorCode {
        self = .legacy(
          Coded(
            code: ErrorCode(errorCode), message: raw.msg ?? raw.message,
            weakPasswordReasons: reasons))
      } else if case .errorCode(let code)? = raw.code {
        self = .versioned(
          Coded(
            code: ErrorCode(code), message: raw.message ?? raw.msg, weakPasswordReasons: reasons))
      } else if let error = raw.error {
        self = .oauth(error: error, description: raw.errorDescription)
      } else {
        self = .legacy(
          Coded(code: .unknown, message: raw.msg ?? raw.message, weakPasswordReasons: reasons))
      }
    }
  }

  /// Every key of the three shapes, so one decode tolerates all of them.
  private struct RawBody: Decodable {
    /// The HTTP status in the legacy shape, the error code in the 2024-01-01 shape.
    enum Code: Decodable {
      case status(Int)
      case errorCode(String)

      init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let status = try? container.decode(Int.self) {
          self = .status(status)
        } else {
          self = .errorCode(try container.decode(String.self))
        }
      }
    }

    struct WeakPassword: Decodable {
      let reasons: [String]?
    }

    let code: Code?
    let errorCode: String?
    let msg: String?
    let message: String?
    let error: String?
    let errorDescription: String?
    let weakPassword: WeakPassword?

    enum CodingKeys: String, CodingKey {
      case code
      case errorCode = "error_code"
      case msg
      case message
      case error
      case errorDescription = "error_description"
      case weakPassword = "weak_password"
    }
  }
}
