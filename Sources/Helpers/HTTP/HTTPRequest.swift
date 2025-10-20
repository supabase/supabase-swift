//
//  HTTPRequest.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct HTTPRequest: Sendable {
  package var url: URL
  package var method: HTTPTypes.HTTPRequest.Method
  package var query: [URLQueryItem]
  package var headers: HTTPFields
  package var body: Data?
  package var timeoutInterval: TimeInterval

  package init(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Data? = nil,
    timeoutInterval: TimeInterval = 60
  ) {
    self.url = url
    self.method = method
    self.query = query
    self.headers = headers
    self.body = body
    self.timeoutInterval = timeoutInterval
  }

  package init?(
    urlString: String,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Data? = nil,
    timeoutInterval: TimeInterval = 60
  ) {
    guard let url = URL(string: urlString) else { return nil }
    self.init(url: url, method: method, query: query, headers: headers, body: body, timeoutInterval: timeoutInterval)
  }

  package func asURLRequest() throws -> URLRequest {
    var urlRequest = URLRequest(url: query.isEmpty ? url : url.appendingQueryItems(query), timeoutInterval: timeoutInterval)
    urlRequest.httpMethod = method.rawValue
    urlRequest.allHTTPHeaderFields = .init(headers.map { ($0.name.rawName, $0.value) }) { $1 }
    urlRequest.httpBody = body
    
    if urlRequest.httpBody != nil, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    return urlRequest
  }
}

extension [URLQueryItem] {
  package mutating func appendOrUpdate(_ queryItem: URLQueryItem) {
    if let index = firstIndex(where: { $0.name == queryItem.name }) {
      self[index] = queryItem
    } else {
      self.append(queryItem)
    }
  }
}
