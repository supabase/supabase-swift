//
//  FoundationExtensions.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking

  package let NSEC_PER_SEC: UInt64 = 1_000_000_000
  package let NSEC_PER_MSEC: UInt64 = 1_000_000
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

    let currentQueryItems = components.percentEncodedQueryItems ?? []

    components.percentEncodedQueryItems =
      currentQueryItems
      + queryItems.map {
        URLQueryItem(
          name: escape($0.name),
          value: $0.value.map(escape)
        )
      }

    if let newURL = components.url {
      self = newURL
    }
  }

  package func appendingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
    var url = self
    url.appendQueryItems(queryItems)
    return url
  }

  // package mutating func appendOrUpdateQueryItems(_ queryItems: [URLQueryItem]) {
  //   guard !queryItems.isEmpty else {
  //     return
  //   }

  //   guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
  //     return
  //   }

  //   var currentQueryItems = components.percentEncodedQueryItems ?? []

  //   for var queryItem in queryItems {
  //     queryItem.name = escape(queryItem.name)
  //     queryItem.value = queryItem.value.map(escape)
  //     if let index = currentQueryItems.firstIndex(where: { $0.name == queryItem.name }) {
  //       currentQueryItems[index] = queryItem
  //     } else {
  //       currentQueryItems.append(queryItem)
  //     }
  //   }

  //   components.percentEncodedQueryItems = currentQueryItems

  //   if let newURL = components.url {
  //     self = newURL
  //   }
  // }

  // package func appendingOrUpdatingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
  //   var url = self
  //   url.appendOrUpdateQueryItems(queryItems)
  //   return url
  // }
}

func escape(_ string: String) -> String {
  string.addingPercentEncoding(withAllowedCharacters: .sbURLQueryAllowed) ?? string
}

extension CharacterSet {
  /// Creates a CharacterSet from RFC 3986 allowed characters.
  ///
  /// RFC 3986 states that the following characters are "reserved" characters.
  ///
  /// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
  /// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
  ///
  /// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
  /// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
  /// should be percent-escaped in the query string.
  static let sbURLQueryAllowed: CharacterSet = {
    let generalDelimitersToEncode = ":#[]@"  // does not include "?" or "/" due to RFC 3986 - Section 3.4
    let subDelimitersToEncode = "!$&'()*+,;="
    let encodableDelimiters = CharacterSet(
      charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

    return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
  }()
}
