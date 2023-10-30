//
//  Result.swift
//  ProductSample
//
//  Created by Guilherme Souza on 19/10/23.
//

import Foundation

extension Result {
  var value: Success? {
    if case let .success(success) = self {
      return success
    }
    return nil
  }
}
