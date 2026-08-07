//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

public import Foundation

public struct PostgrestError: Error, Codable, Sendable {
  /// Additional detail about the error, as returned by PostgREST in the `details` field.
  public let details: String?
  public let hint: String?
  public let code: String?
  public let message: String

  @available(*, deprecated, renamed: "details")
  public var detail: String? { details }

  public init(
    details: String? = nil,
    hint: String? = nil,
    code: String? = nil,
    message: String
  ) {
    self.hint = hint
    self.details = details
    self.code = code
    self.message = message
  }

  @available(*, deprecated, renamed: "init(details:hint:code:message:)")
  public init(
    detail: String?,
    hint: String? = nil,
    code: String? = nil,
    message: String
  ) {
    self.init(details: detail, hint: hint, code: code, message: message)
  }
}

extension PostgrestError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
