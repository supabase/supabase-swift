//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPClientSessionConfiguration {
  /// The `URLSessionConfiguration` to use for network requests.
  public var sessionConfiguration: URLSessionConfiguration
  /// An optional `URLSessionDelegate` for advanced session management.
  public var sessionDelegate: (any URLSessionDelegate)?
  /// An optional `OperationQueue` for handling delegate calls.
  public var sessionDelegateQueue: OperationQueue?

  public init(
    sessionConfiguration: URLSessionConfiguration = .default,
    sessionDelegate: (any URLSessionDelegate)? = nil,
    sessionDelegateQueue: OperationQueue? = nil
  ) {
    self.sessionConfiguration = sessionConfiguration
    self.sessionDelegate = sessionDelegate
    self.sessionDelegateQueue = sessionDelegateQueue
  }
}

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

extension OperationQueue {
  static func serial() -> OperationQueue {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }
}

package struct HTTPClient: HTTPClientType {
  let session: URLSession
  let interceptors: [any HTTPClientInterceptor]

  let dataLoader = DataLoader()

  package init(
    configuration: HTTPClientSessionConfiguration,
    interceptors: [any HTTPClientInterceptor]
  ) {
    self.session = URLSession(
      configuration: configuration.sessionConfiguration,
      delegate: dataLoader,
      delegateQueue: configuration.sessionDelegateQueue ?? .serial()
    )
    self.interceptors = interceptors

    dataLoader.userSessionDelegate = configuration.sessionDelegate
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var urlRequest = URLRequest(
      url: request.query.isEmpty ? request.url : request.url.appendingQueryItems(request.query))
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.allHTTPHeaderFields = .init(request.headers.map { ($0.name.rawName, $0.value) }) {
      $1
    }

    if let body = request.body {
      if case .url(let url) = body {
        return try await dataLoader.startUploadTask(
          session.uploadTask(with: urlRequest, fromFile: url),
          session: session,
          delegate: nil
        )
      } else {
        let uploadData = try encode(body, in: &urlRequest)
        if let uploadData {
          let task = session.uploadTask(with: urlRequest, from: uploadData)
          return try await dataLoader.startUploadTask(
            task, session: session, delegate: nil)
        } else {
          fatalError("Bad request")
        }
      }
    } else {
      let task = session.dataTask(with: urlRequest)
      return try await dataLoader.startDataTask(
        task,
        session: session,
        delegate: nil
      )
    }
  }

  private func encode(
    _ body: HTTPRequest.Body,
    in request: inout URLRequest
  ) throws -> Data? {
    switch body {
    case .url(let url):
      return try Data(contentsOf: url)

    case .data(let data):
      return data

    case let .json(value, encoder):
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }

      return try encoder.encode(value)
    }
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse
}
