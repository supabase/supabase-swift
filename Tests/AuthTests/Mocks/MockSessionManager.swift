//
//  MockSessionManager.swift
//
//
//  Created by Guilherme Souza on 16/02/24.
//

@testable import Auth
import ConcurrencyExtras
import Foundation

final class MockSessionManager: SessionManager {
  private let _returnSession = LockIsolated(Result<Session, Error>?.none)
  var returnSession: Result<Session, Error>? {
    get { _returnSession.value }
    set { _returnSession.setValue(newValue) }
  }

  func session(shouldValidateExpiration _: Bool) async throws -> Auth.Session {
    try returnSession!.get()
  }

  func update(_: Auth.Session) async throws {}

  private let _removeCallCount = LockIsolated(0)
  var removeCallCount: Int {
    get { _removeCallCount.value }
    set { _removeCallCount.setValue(newValue) }
  }

  var removeCalled: Bool { removeCallCount > 0 }
  func remove() async {
    _removeCallCount.withValue { $0 += 1 }
  }
}
