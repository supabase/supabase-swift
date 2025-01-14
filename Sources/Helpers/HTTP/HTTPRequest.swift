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
  package var body: Body?

  package init(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Body? = nil
  ) {
    self.url = url
    self.method = method
    self.query = query
    self.headers = headers
    self.body = body
  }

  package init(
    url: URL,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Data?
  ) {
    self.url = url
    self.method = method
    self.query = query

    self.body = body.map(Body.data)

    var headers = headers

    if body != nil, headers[.contentType] == nil {
      headers[.contentType] = "application/json"
    }

    self.headers = headers
  }

  package init?(
    urlString: String,
    method: HTTPTypes.HTTPRequest.Method,
    query: [URLQueryItem] = [],
    headers: HTTPFields = [:],
    body: Body?
  ) {
    guard let url = URL(string: urlString) else { return nil }
    self.init(url: url, method: method, query: query, headers: headers, body: body)
  }

  package enum Body: Sendable {
    case url(URL)
    case data(Data)
    case json(any Encodable & Sendable, encoder: JSONEncoder = JSONEncoder())
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
