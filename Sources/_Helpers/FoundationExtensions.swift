//
//  FoundationExtensions.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation

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

extension URL {
  package func appendingQueryItem(_ queryItem: URLQueryItem) -> URL {
    appendingQueryItems([queryItem])
  }

  package func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return self
    }

    let currentQueryItems = components.queryItems ?? []
    components.queryItems = currentQueryItems + queryItems

    return components.url ?? self
  }
}
