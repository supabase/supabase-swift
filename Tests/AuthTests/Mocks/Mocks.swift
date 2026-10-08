//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import ConcurrencyExtras
import Foundation
import TestHelpers
import IssueReporting

@testable import Auth

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension Session {
  static let valid = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    expiresAt: Date().addingTimeInterval(120).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )

  static let expired = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 30,
    expiresAt: Date().addingTimeInterval(30).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}
