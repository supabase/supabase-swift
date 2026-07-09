//
//  HTTPResponse.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation

/// The status line and headers of a response, without the body.
///
/// Used on its own for streaming responses (where the body is delivered
/// separately as an `AsyncSequence`) and embedded in ``HTTPResponse`` for
/// buffered responses.
package struct HTTPResponseHead: Sendable {
  package let status: Int
  package let headers: [String: String]

  package init(status: Int, headers: [String: String]) {
    self.status = status
    self.headers = headers
  }

  package func header(_ name: String) -> String? {
    // HTTP header names are case-insensitive.
    if let exact = headers[name] { return exact }
    let lowered = name.lowercased()
    return headers.first { $0.key.lowercased() == lowered }?.value
  }

  package var isSuccess: Bool { (200..<300).contains(status) }
}

/// A fully-buffered response.
package struct HTTPResponse: Sendable {
  package let head: HTTPResponseHead
  package let body: Data

  package init(head: HTTPResponseHead, body: Data) {
    self.head = head
    self.body = body
  }
}

/// A streaming response: the head arrives first, the body is an async sequence
/// of `Data` chunks (used for large downloads and event streams).
package struct HTTPResponseStream: Sendable {
  package let head: HTTPResponseHead
  package let body: AsyncThrowingStream<Data, any Error>

  package init(head: HTTPResponseHead, body: AsyncThrowingStream<Data, any Error>) {
    self.head = head
    self.body = body
  }
}
