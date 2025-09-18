import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A protocol that all Supabase errors should conform to for consistent error handling.
public protocol SupabaseError: LocalizedError, Sendable {
  /// The error code associated with this error.
  var errorCode: String { get }
  
  /// The underlying data that caused this error, if any.
  var underlyingData: Data? { get }
  
  /// The HTTP response that caused this error, if any.
  var underlyingResponse: HTTPURLResponse? { get }
  
  /// Additional context about the error.
  var context: [String: String] { get }
}

/// A base error type that provides common functionality for all Supabase errors.
public struct BaseSupabaseError: SupabaseError {
  public let errorCode: String
  public let underlyingData: Data?
  public let underlyingResponse: HTTPURLResponse?
  public let context: [String: String]
  public let message: String
  
  public init(
    errorCode: String,
    message: String,
    underlyingData: Data? = nil,
    underlyingResponse: HTTPURLResponse? = nil,
    context: [String: String] = [:]
  ) {
    self.errorCode = errorCode
    self.message = message
    self.underlyingData = underlyingData
    self.underlyingResponse = underlyingResponse
    self.context = context
  }
  
  public var errorDescription: String? {
    return message
  }
}

/// Common error codes used across all Supabase modules.
public enum SupabaseErrorCode: String, CaseIterable {
  // Network errors
  case networkError = "network_error"
  case timeoutError = "timeout_error"
  case connectionError = "connection_error"
  
  // Authentication errors
  case sessionMissing = "session_missing"
  case sessionExpired = "session_expired"
  case invalidCredentials = "invalid_credentials"
  case userNotFound = "user_not_found"
  case emailExists = "email_exists"
  case phoneExists = "phone_exists"
  case weakPassword = "weak_password"
  case mfaRequired = "mfa_required"
  case mfaInvalid = "mfa_invalid"
  
  // Database errors
  case queryError = "query_error"
  case constraintViolation = "constraint_violation"
  case recordNotFound = "record_not_found"
  case permissionDenied = "permission_denied"
  
  // Storage errors
  case fileNotFound = "file_not_found"
  case fileTooLarge = "file_too_large"
  case invalidFileType = "invalid_file_type"
  case uploadFailed = "upload_failed"
  case downloadFailed = "download_failed"
  
  // Functions errors
  case functionNotFound = "function_not_found"
  case functionError = "function_error"
  case relayError = "relay_error"
  
  // Realtime errors
  case connectionFailed = "connection_failed"
  case subscriptionFailed = "subscription_failed"
  case maxRetryAttemptsReached = "max_retry_attempts_reached"
  
  // Generic errors
  case unknown = "unknown"
  case validationFailed = "validation_failed"
  case configurationError = "configuration_error"
  case internalError = "internal_error"
}

/// A utility for creating consistent error messages and debugging information.
public struct ErrorDebugInfo {
  public let timestamp: Date
  public let module: String
  public let operation: String
  public let requestId: String?
  public let additionalInfo: [String: String]
  
  public init(
    module: String,
    operation: String,
    requestId: String? = nil,
    additionalInfo: [String: String] = [:]
  ) {
    self.timestamp = Date()
    self.module = module
    self.operation = operation
    self.requestId = requestId
    self.additionalInfo = additionalInfo
  }
  
  public var description: String {
    var info = "Module: \(module), Operation: \(operation)"
    if let requestId = requestId {
      info += ", Request ID: \(requestId)"
    }
    if !additionalInfo.isEmpty {
      let infoString = additionalInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
      info += ", Additional Info: \(infoString)"
    }
    return info
  }
}

/// Extension to provide common error creation methods.
extension SupabaseError {
  /// Creates a standardized error with debug information.
  public static func create(
    code: SupabaseErrorCode,
    message: String,
    module: String,
    operation: String,
    underlyingData: Data? = nil,
    underlyingResponse: HTTPURLResponse? = nil,
    requestId: String? = nil,
    additionalInfo: [String: String] = [:]
  ) -> BaseSupabaseError {
    let debugInfo = ErrorDebugInfo(
      module: module,
      operation: operation,
      requestId: requestId,
      additionalInfo: additionalInfo
    )
    
    var context: [String: String] = [
      "debugInfo": debugInfo.description,
      "module": module,
      "operation": operation
    ]
    
    if let requestId = requestId {
      context["requestId"] = requestId
    }
    
    context.merge(additionalInfo) { _, new in new }
    
    return BaseSupabaseError(
      errorCode: code.rawValue,
      message: message,
      underlyingData: underlyingData,
      underlyingResponse: underlyingResponse,
      context: context
    )
  }
}
