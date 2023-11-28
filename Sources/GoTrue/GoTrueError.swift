import Foundation

public enum GoTrueError: LocalizedError, Sendable {
  case missingExpClaim
  case malformedJWT
  case sessionNotFound
  case api(APIError)
  case pkce(PKCEFailureReason)
  case invalidImplicitGrantFlowURL

  public struct APIError: Error, Decodable, Sendable {
    public var message: String?
    public var msg: String?
    public var code: Int?
    public var error: String?
    public var errorDescription: String?
  }

  public enum PKCEFailureReason: Sendable {
    case codeVerifierNotFound
    case invalidPKCEFlowURL
  }

  public var errorDescription: String? {
    switch self {
    case .missingExpClaim: return "Missing expiration claim on access token."
    case .malformedJWT: return "A malformed JWT received."
    case .sessionNotFound: return "Unable to get a valid session."
    case let .api(error): return error.errorDescription ?? error.message ?? error.msg
    case .pkce(.codeVerifierNotFound): return "A code verifier wasn't found in PKCE flow."
    case .pkce(.invalidPKCEFlowURL): return "Not a valid PKCE flow url."
    case .invalidImplicitGrantFlowURL:
      return "Not a valid implicit grant flow url."
    }
  }
}
