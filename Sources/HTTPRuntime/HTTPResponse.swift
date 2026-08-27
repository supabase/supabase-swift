//
//  HTTPResponse.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
package import Foundation
package import HTTPTypes

/// A fully-buffered response: an `HTTPTypes.HTTPResponse` head plus its body.
package struct HTTPBufferedResponse: Sendable {
  package let head: HTTPResponse
  package let body: Data

  package init(head: HTTPResponse, body: Data) {
    self.head = head
    self.body = body
  }
}

/// A streaming response: the head arrives first, the body is an async sequence
/// of `Data` chunks (used for large downloads and event streams).
package struct HTTPStreamedResponse: Sendable {
  package let head: HTTPResponse
  package let body: AsyncThrowingStream<Data, any Error>

  package init(head: HTTPResponse, body: AsyncThrowingStream<Data, any Error>) {
    self.head = head
    self.body = body
  }
}
