import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct StorageError: SupabaseError, Decodable, Sendable {
  public var statusCode: String?
  public var message: String
  public var error: String?
  public var underlyingData: Data?
  public var underlyingResponse: HTTPURLResponse?

  public init(
    statusCode: String? = nil, 
    message: String, 
    error: String? = nil,
    underlyingData: Data? = nil,
    underlyingResponse: HTTPURLResponse? = nil
  ) {
    self.statusCode = statusCode
    self.message = message
    self.error = error
    self.underlyingData = underlyingData
    self.underlyingResponse = underlyingResponse
  }
  
  // MARK: - Decodable Support
  
  private enum CodingKeys: String, CodingKey {
    case statusCode, message, error
  }
  
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
    self.message = try container.decode(String.self, forKey: .message)
    self.error = try container.decodeIfPresent(String.self, forKey: .error)
    self.underlyingData = nil
    self.underlyingResponse = nil
  }
  
  // MARK: - SupabaseError Protocol Conformance
  
  public var errorCode: String {
    // Map common storage error messages to error codes
    if let error = error {
      switch error.lowercased() {
      case "file not found", "object not found":
        return SupabaseErrorCode.fileNotFound.rawValue
      case "file too large", "object too large":
        return SupabaseErrorCode.fileTooLarge.rawValue
      case "invalid file type", "unsupported file type":
        return SupabaseErrorCode.invalidFileType.rawValue
      case "upload failed":
        return SupabaseErrorCode.uploadFailed.rawValue
      case "download failed":
        return SupabaseErrorCode.downloadFailed.rawValue
      default:
        return SupabaseErrorCode.unknown.rawValue
      }
    }
    return SupabaseErrorCode.unknown.rawValue
  }
  
  public var context: [String: String] {
    var context: [String: String] = [:]
    if let statusCode = statusCode {
      context["statusCode"] = statusCode
    }
    if let error = error {
      context["error"] = error
    }
    return context
  }
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
