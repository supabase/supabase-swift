//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 27/10/23.
//

import _Helpers
import ConcurrencyExtras
import Foundation
import TestHelpers
import XCTestDynamicOverlay

@testable import Auth

let clientURL = URL(string: "http://localhost:54321/auth/v1")!

extension Session {
  static let validSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 120,
    expiresAt: Date().addingTimeInterval(120).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )

  static let expiredSession = Session(
    accessToken: "accesstoken",
    tokenType: "bearer",
    expiresIn: 60,
    expiresAt: Date().addingTimeInterval(60).timeIntervalSince1970,
    refreshToken: "refreshtoken",
    user: User(fromMockNamed: "user")
  )
}
