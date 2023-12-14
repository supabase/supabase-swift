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
    message: "Access to the default JSONEncoder instance will be removed on the next major release, please use your own instance of JSONEncoder."
  )
  public static var goTrue: JSONEncoder {
    auth
  }
}

extension JSONDecoder {
  @available(
    *,
    deprecated,
    message: "Access to the default JSONDecoder instance will be removed on the next major release, please use your own instance of JSONDecoder."
  )
  public static var goTrue: JSONDecoder {
    auth
  }
}
