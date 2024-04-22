//
//  MockSessionManager.swift
//
//
//  Created by Guilherme Souza on 16/02/24.
//

@testable import Auth
import Foundation
import XCTestDynamicOverlay

extension SessionManager {
  static let mock = SessionManager(
    session: unimplemented("SessionManager.session"),
    update: unimplemented("SessionManager.update"),
    remove: unimplemented("SessionManager.remove"),
    refreshSession: unimplemented("SessionManager.refreshSession")
  )
}
