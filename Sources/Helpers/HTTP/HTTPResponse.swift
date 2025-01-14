//
//  HTTPResponse.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package struct HTTPResponse: Sendable {
  package let body: Body
  package let headers: HTTPFields
  package let statusCode: Int

  package let underlyingResponse: HTTPURLResponse

  package init(body: Body, response: HTTPURLResponse) {
    self.body = body
    headers = HTTPFields(response.allHeaderFields as? [String: String] ?? [:])
    statusCode = response.statusCode
    underlyingResponse = response
  }

  package final class Body: AsyncSequence, Sendable {
    package typealias AsyncIterator = AsyncStream<Data>.AsyncIterator
    package typealias Element = Data
    package typealias Failure = Never

    let stream: AsyncStream<Data>
    let continuation: AsyncStream<Data>.Continuation

    let data = LockIsolated<Data?>(nil)

    package init() {
      (stream, continuation) = AsyncStream<Data>.makeStream()
    }

    package func makeAsyncIterator() -> AsyncIterator {
      stream.makeAsyncIterator()
    }

    package func collect() async -> Data {
      if let data = data.value {
        return data
      }

      let data = await stream.reduce(into: Data()) { $0 += $1 }
      self.data.setValue(data)
      return data
    }

    package func append(_ data: Data) {
      continuation.yield(data)
    }

    package func finalize() {
      continuation.finish()
    }

    package static func data(_ data: Data) -> Self {
      let body = Self()
      body.append(data)
      body.finalize()
      return body
    }

    package static func string(_ string: String, encoding: String.Encoding = .utf8) -> Self {
      .data(string.data(using: encoding)!)
    }
  }
}

extension HTTPResponse {
  package func data() async -> Data {
    await body.collect()
  }

  package func decoded<T: Decodable>(
    as _: T.Type = T.self,
    decoder: JSONDecoder = JSONDecoder()
  ) async throws -> T {
    try await decoder.decode(T.self, from: body.collect())
  }
}
