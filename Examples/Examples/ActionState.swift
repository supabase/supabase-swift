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
