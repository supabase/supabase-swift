//
//  PostgrestError.swift
//
//
//  Created by Guilherme Souza on 27/01/24.
//

import Foundation

public struct PostgrestError: Error, Codable, Sendable {
  public let detail: String?
  public let hint: String?
  public let code: String?
  public let message: String

  public init(
    detail: String? = nil,
    hint: String? = nil,
    code: String? = nil,
    message: String
  ) {
    self.hint = hint
    self.detail = detail
    self.code = code
    self.message = message
  }
}

extension PostgrestError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
