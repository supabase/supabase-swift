//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Describes how many times the provided sequence can be iterated.
public enum IterationBehavior: Sendable {

  /// The input sequence can only be iterated once.
  ///
  /// If a retry or a redirect is encountered, fail the call with
  /// a descriptive error.
  case single

  /// The input sequence can be iterated multiple times.
  ///
  /// Supports retries and redirects, as a new iterator is created each
  /// time.
  case multiple
}

// MARK: - Internal

/// A type-erasing closure-based iterator.
@usableFromInline struct AnyIterator<Element: Sendable>: AsyncIteratorProtocol {

  /// The closure that produces the next element.
  private let produceNext: () async throws -> Element?

  /// Creates a new type-erased iterator from the provided iterator.
  /// - Parameter iterator: The iterator to type-erase.
  @usableFromInline init<Iterator: AsyncIteratorProtocol>(_ iterator: Iterator)
  where Iterator.Element == Element {
    var iterator = iterator
    self.produceNext = { try await iterator.next() }
  }

  /// Advances the iterator to the next element and returns it asynchronously.
  ///
  /// - Returns: The next element in the sequence, or `nil` if there are no more elements.
  /// - Throws: An error if there is an issue advancing the iterator or retrieving the next element.
  public mutating func next() async throws -> Element? { try await produceNext() }
}

/// A type-erased async sequence that wraps input sequences.
@usableFromInline struct AnySequence<Element: Sendable>: AsyncSequence, Sendable {

  /// The type of the type-erased iterator.
  @usableFromInline typealias AsyncIterator = AnyIterator<Element>

  /// A closure that produces a new iterator.
  @usableFromInline let produceIterator: @Sendable () -> AsyncIterator

  /// Creates a new sequence.
  /// - Parameter sequence: The input sequence to type-erase.
  @usableFromInline init<Upstream: AsyncSequence>(_ sequence: Upstream)
  where Upstream.Element == Element, Upstream: Sendable {
    self.produceIterator = { .init(sequence.makeAsyncIterator()) }
  }

  @usableFromInline func makeAsyncIterator() -> AsyncIterator { produceIterator() }
}

/// An async sequence wrapper for a sync sequence.
@usableFromInline struct WrappedSyncSequence<Upstream: Sequence & Sendable>: AsyncSequence, Sendable
where Upstream.Element: Sendable {

  /// The type of the iterator.
  @usableFromInline typealias AsyncIterator = Iterator<Element>

  /// The element type.
  @usableFromInline typealias Element = Upstream.Element

  /// An iterator type that wraps a sync sequence iterator.
  @usableFromInline struct Iterator<IteratorElement: Sendable>: AsyncIteratorProtocol {

    /// The element type.
    @usableFromInline typealias Element = IteratorElement

    /// The underlying sync sequence iterator.
    var iterator: any IteratorProtocol<Element>

    @usableFromInline mutating func next() async throws -> IteratorElement? { iterator.next() }
  }

  /// The underlying sync sequence.
  @usableFromInline let sequence: Upstream

  /// Creates a new async sequence with the provided sync sequence.
  /// - Parameter sequence: The sync sequence to wrap.
  @usableFromInline init(sequence: Upstream) { self.sequence = sequence }

  @usableFromInline func makeAsyncIterator() -> AsyncIterator {
    Iterator(iterator: sequence.makeIterator())
  }
}

/// An empty async sequence.
@usableFromInline struct EmptySequence<Element: Sendable>: AsyncSequence, Sendable {

  /// The type of the empty iterator.
  @usableFromInline typealias AsyncIterator = EmptyIterator<Element>

  /// An async iterator of an empty sequence.
  @usableFromInline struct EmptyIterator<IteratorElement: Sendable>: AsyncIteratorProtocol {

    @usableFromInline mutating func next() async throws -> IteratorElement? { nil }
  }

  /// Creates a new empty async sequence.
  @usableFromInline init() {}

  @usableFromInline func makeAsyncIterator() -> AsyncIterator { EmptyIterator() }
}
