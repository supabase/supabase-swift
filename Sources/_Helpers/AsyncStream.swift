//
//  File.swift
//
//
//  Created by Guilherme Souza on 26/10/23.
//

import Foundation

extension AsyncStream {
#if compiler(<5.9)
  @_spi(Internal)
  public static func makeStream(
    of elementType: Element.Type = Element.self,
    bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded
  ) -> (stream: Self, continuation: Continuation) {
    var continuation: Continuation!
    return (Self(elementType, bufferingPolicy: limit) { continuation = $0 }, continuation)
  }
#endif
}
