//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 14/12/23.
//

import Foundation

@available(*, deprecated, renamed: "AuthClient")
public typealias GoTrueClient = AuthClient

@available(*, deprecated, renamed: "AuthMFA")
public typealias GoTrueMFA = AuthMFA

@available(*, deprecated, renamed: "AuthLocalStorage")
public typealias GoTrueLocalStorage = AuthLocalStorage

@available(*, deprecated, renamed: "AuthMetaSecurity")
public typealias GoTrueMetaSecurity = AuthMetaSecurity

@available(*, deprecated, renamed: "AuthError")
public typealias GoTrueError = AuthError

extension JSONEncoder {
  @available(
    *,
    deprecated,
    renamed: "AuthClient.Configuration.jsonEncoder",
    message: "Access to the default JSONEncoder instance moved to AuthClient.Configuration.jsonEncoder"
  )
  public static var goTrue: JSONEncoder {
    AuthClient.Configuration.jsonEncoder
  }
}

extension JSONDecoder {
  @available(
    *,
    deprecated,
    renamed: "AuthClient.Configuration.jsonDecoder",
    message: "Access to the default JSONDecoder instance moved to AuthClient.Configuration.jsonDecoder"
  )
  public static var goTrue: JSONDecoder {
    AuthClient.Configuration.jsonDecoder
  }
}
