//
//  ActionState.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import Foundation

enum ActionState<Success, Failure: Error> {
  case idle
  case inFlight
  case result(Result<Success, Failure>)
}

extension Result where Failure == Error {
  init(catching operation: () async throws -> Success) async {
    do {
      let value = try await operation()
      self = .success(value)
    } catch {
      self = .failure(error)
    }
  }
}
