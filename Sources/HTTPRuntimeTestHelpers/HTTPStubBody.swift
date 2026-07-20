//
//  HTTPStubBody.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
package import Foundation

/// The canned response body for an ``HTTPStub``.
package enum HTTPStubBody: Sendable {
  case empty
  case string(String)
  case data(Data)
  /// Chunks delivered over time — for stubbing `HTTPTransport.stream()`.
  case stream(AsyncStream<Data>)
}
