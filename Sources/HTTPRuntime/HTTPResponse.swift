//
//  HTTPResponse.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//
public import Foundation

/// The status line and headers of a response, without the body.
///
/// Used on its own for streaming responses (where the body is delivered
/// separately as an `AsyncSequence`) and embedded in ``HTTPResponse`` for
/// buffered responses.
public struct HTTPResponseHead: Sendable {
  public let status: Int
  public let headers: [String: String]

  public init(status: Int, headers: [String: String]) {
    self.status = status
    self.headers = headers
  }

  public func header(_ name: String) -> String? {
    // HTTP header names are case-insensitive.
    if let exact = headers[name] { return exact }
    let lowered = name.lowercased()
    return headers.first { $0.key.lowercased() == lowered }?.value
  }

  public var isSuccess: Bool { (200..<300).contains(status) }
}

/// A fully-buffered response.
public struct HTTPResponse: Sendable {
  public let head: HTTPResponseHead
  public let body: Data

  public init(head: HTTPResponseHead, body: Data) {
    self.head = head
    self.body = body
  }

  public var status: Int { head.status }
  public func header(_ name: String) -> String? { head.header(name) }
  public var isSuccess: Bool { head.isSuccess }
}

/// A streaming response: the head arrives first, the body is an async sequence
/// of `Data` chunks (used for large downloads and event streams).
public struct HTTPResponseStream: Sendable {
  public let head: HTTPResponseHead
  public let body: AsyncThrowingStream<Data, any Error>

  public init(head: HTTPResponseHead, body: AsyncThrowingStream<Data, any Error>) {
    self.head = head
    self.body = body
  }
}
