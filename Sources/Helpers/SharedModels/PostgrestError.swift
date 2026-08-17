//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

public import Foundation

public struct PostgrestError: Error, Decodable, Sendable {
  /// Additional detail about the error, as returned by PostgREST in the `details` field.
  public let details: String?
  public let hint: String?
  public let code: String?
  public let message: String

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
}

extension PostgrestError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
