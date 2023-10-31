//
//  UseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Storage

protocol UseCase<Input, Output>: Sendable {
  associatedtype Input: Sendable
  associatedtype Output: Sendable

  func execute(input: Input) -> Output
}

extension UseCase where Input == Void {
  func execute() -> Output {
    execute(input: ())
  }
}
