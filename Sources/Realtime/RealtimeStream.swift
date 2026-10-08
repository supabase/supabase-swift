//
//  RealtimeStream.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

/// A non-throwing async sequence of Realtime events.
///
/// Each call to a stream-returning API makes a new, independent sequence that is registered
/// before the call returns. Ending the iteration, by leaving the loop or cancelling the task,
/// removes the underlying listener.
///
/// Elements are buffered without a limit, so a consumer that stops iterating without ending the
/// loop holds every later element in memory.
public struct RealtimeStream<Element: Sendable>: AsyncSequence, Sendable {
  /// A Realtime stream never throws. Errors arrive as elements or on the status streams.
  public typealias Failure = Never

  private let makeNext: @Sendable () -> @concurrent () async -> Element?

  /// Wraps `base`, keeping the elements `transform` maps to a non-`nil` value.
  package init<Base: Sendable>(
    _ base: AsyncStream<Base>, transform: @escaping @Sendable (Base) -> Element?
  ) {
    makeNext = {
      var iterator = base.makeAsyncIterator()
      return {
        while let value = await iterator.next() {
          if let element = transform(value) { return element }
        }
        return nil
      }
    }
  }

  /// Wraps `base` unchanged.
  package init(_ base: AsyncStream<Element>) {
    self.init(base) { $0 }
  }

  /// Makes the iterator for a `for await` loop.
  public func makeAsyncIterator() -> Iterator {
    Iterator(produceNext: makeNext())
  }

  /// The iterator of a ``RealtimeStream``.
  public struct Iterator: AsyncIteratorProtocol {
    let produceNext: @concurrent () async -> Element?

    /// The next element, or `nil` once the stream ends.
    public mutating func next() async -> Element? {
      await produceNext()
    }
  }
}
