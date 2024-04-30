//
//  HTTPRequest.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation

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

  package var urlRequest: URLRequest {
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = method.rawValue
    urlRequest.allHTTPHeaderFields = headers.dictionary
    urlRequest.httpBody = body
    return urlRequest
  }
}

extension HTTPRequest {
  package init?(
    urlString: String,
    method: HTTPMethod,
    headers: HTTPHeaders = [:],
    body: Data?
  ) {
    guard let url = URL(string: urlString) else { return nil }
    self.init(url: url, method: method, headers: headers, body: body)
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

package struct HTTPResponse: Sendable {
  package let data: Data
  package let headers: HTTPHeaders
  package let statusCode: Int

  package let underlyingResponse: HTTPURLResponse

  package init(data: Data, response: HTTPURLResponse) {
    self.data = data
    headers = HTTPHeaders(response.allHeaderFields as? [String: String] ?? [:])
    statusCode = response.statusCode
    underlyingResponse = response
  }
}

extension HTTPResponse {
  package func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse
}

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

package actor _HTTPClient: HTTPClientType {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  let interceptors: [any HTTPClientInterceptor]

  package init(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    interceptors: [any HTTPClientInterceptor]
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var next: @Sendable (HTTPRequest) async throws -> HTTPResponse = { _request in
      let urlRequest = _request.urlRequest
      let (data, response) = try await self.fetch(urlRequest)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: data, response: httpURLResponse)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept($0, next: tmp)
      }
    }

    return try await next(request)
  }
}

package struct LoggerInterceptor: HTTPClientInterceptor {
  let logger: any SupabaseLogger

  package init(logger: any SupabaseLogger) {
    self.logger = logger
  }

  package func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse {
    let id = UUID().uuidString
    logger.verbose(
      """
      Request [\(id)]: \(request.method.rawValue) \(request.url.absoluteString
        .removingPercentEncoding ?? "")
      Body: \(stringfy(request.body))
      """
    )

    do {
      let response = try await next(request)
      logger.verbose(
        """
        Response [\(id)]: Status code: \(response.statusCode) Content-Length: \(
          response.underlyingResponse.expectedContentLength
        )
        Body: \(stringfy(response.data))
        """
      )
      return response
    } catch {
      logger.error("Response [\(id)]: Failure \(error)")
      throw error
    }
  }
}
