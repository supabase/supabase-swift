//
//  FoundationExtensions.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking

  package let NSEC_PER_SEC: UInt64 = 1_000_000_000
  package let NSEC_PER_MSEC: UInt64 = 1_000_000
#endif

extension Result {
  package var value: Success? {
    if case .success(let value) = self {
      value
    } else {
      nil
    }
  }

  package var error: Failure? {
    if case .failure(let error) = self {
      error
    } else {
      nil
    }
  }
}

extension URL {
  // package var queryItems: [URLQueryItem] {
  //   get {
  //     URLComponents(url: self, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
  //   }
  //   set {
  //     appendOrUpdateQueryItems(newValue)
  //   }
  // }

  package mutating func appendQueryItems(_ queryItems: [URLQueryItem]) {
    guard !queryItems.isEmpty else {
      return
    }

    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return
    }

    let encoding = URLEncoding.queryString

    func query(_ parameters: [URLQueryItem]) -> String {
      var components: [(String, String)] = []

      for param in parameters.sorted(by: { $0.name < $1.name }) {
        components += encoding.queryComponents(fromKey: param.name, value: param.value!)
      }
      return components.map { "\($0)=\($1)" }.joined(separator: "&")
    }

    let percentEncodedQuery =
      (components.percentEncodedQuery.map { $0 + "&" } ?? "") + query(queryItems)
    components.percentEncodedQuery = percentEncodedQuery

    if let newURL = components.url {
      self = newURL
    }
  }

  package func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
    var url = self
    url.appendQueryItems(queryItems)
    return url
  }
}
