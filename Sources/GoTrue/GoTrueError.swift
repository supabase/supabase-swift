import Foundation

public enum GoTrueError: LocalizedError, Sendable {
  case missingExpClaim
  case malformedJWT
  case sessionNotFound
  case api(APIError)

  public struct APIError: Error, Decodable, Sendable {
    public var message: String?
    public var msg: String?
    public var code: Int?
    public var error: String?
    public var errorDescription: String?

    private enum CodingKeys: String, CodingKey {
      case message
      case msg
      case code
      case error
      case errorDescription = "error_description"
    }
  }

  public var errorDescription: String? {
    switch self {
    case .missingExpClaim: return "Missing expiration claim on access token."
    case .malformedJWT: return "A malformed JWT received."
    case .sessionNotFound: return "Unable to get a valid session."
    case let .api(error): return error.errorDescription ?? error.message ?? error.msg
    }
  }
}
