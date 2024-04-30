//
//  HTTPRequest.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct HTTPRequest: Sendable {
  package var url: URL
  package var method: HTTPMethod
  package var headers: HTTPHeaders
  package var body: Data?

  package init(
    url: URL,
    method: HTTPMethod,
    headers: HTTPHeaders = [:],
    body: Data? = nil
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }

  package init?(
    urlString: String,
    method: HTTPMethod,
    headers: HTTPHeaders = [:],
    body: Data?
  ) {
    guard let url = URL(string: urlString) else { return nil }
    self.init(url: url, method: method, headers: headers, body: body)
  }

  package var urlRequest: URLRequest {
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = method.rawValue
    urlRequest.allHTTPHeaderFields = headers.dictionary
    urlRequest.httpBody = body
    return urlRequest
  }
}

package enum HTTPMethod: String, Sendable {
  case get = "GET"
  case head = "HEAD"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
  case connect = "CONNECT"
  case trace = "TRACE"
  case patch = "PATCH"
  case options = "OPTIONS"
}
