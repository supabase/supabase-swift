//
//  ConcurrencyShims.swift
//
//
//  Created by Guilherme Souza on 11/01/24.
//

import Combine
import Foundation

@available(
  iOS,
  deprecated: 15.0,
  message: "This extension is only useful when targeting iOS versions earlier than 15"
)
extension Publisher {
  @_spi(Internal)
  public var values: AsyncThrowingStream<Output, Error> {
    AsyncThrowingStream { continuation in
      var cancellable: AnyCancellable?
      let onTermination = { cancellable?.cancel() }
      continuation.onTermination = { @Sendable _ in
        onTermination()
      }

      cancellable = sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            continuation.finish()
          case let .failure(error):
            continuation.finish(throwing: error)
          }
        },
        receiveValue: { value in
          continuation.yield(value)
        }
      )
    }
  }
}

@available(
  iOS,
  deprecated: 15.0,
  message: "This extension is only useful when targeting iOS versions earlier than 15"
)
extension Publisher where Failure == Never {
  @_spi(Internal)
  public var values: AsyncStream<Output> {
    AsyncStream { continuation in
      var cancellable: AnyCancellable?
      let onTermination = { cancellable?.cancel() }
      continuation.onTermination = { @Sendable _ in
        onTermination()
      }

      cancellable = sink(
        receiveCompletion: { _ in
          continuation.finish()
        },
        receiveValue: { value in
          continuation.yield(value)
        }
      )
    }
  }
}
