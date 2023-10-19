//
//  UseCase.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation
import Storage

protocol UseCase<Input, Output> {
  associatedtype Input
  associatedtype Output

  func execute(input: Input) -> Output
}
