//
//  FoundationExtensions.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

#if canImport(FoundationNetworking)
  import FoundationNetworking

  package let NSEC_PER_SEC: UInt64 = 1000000000
  package let NSEC_PER_MSEC: UInt64 = 1000000
#endif

extension Result {
  package var value: Success? {
    if case let .success(value) = self {
      value
    } else {
      nil
    }
  }

  package var error: Failure? {
    if case let .failure(error) = self {
      error
    } else {
      nil
    }
  }
}
