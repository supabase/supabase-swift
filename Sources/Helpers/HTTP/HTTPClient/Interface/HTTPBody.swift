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

import struct Foundation.Data  // only for convenience initializers
import protocol Foundation.LocalizedError
import class Foundation.NSLock

/// A body of an HTTP request or HTTP response.
///
/// Under the hood, it represents an async sequence of byte chunks.
///
/// ## Creating a body from a buffer
/// There are convenience initializers to create a body from common types, such
/// as `Data`, `[UInt8]`, `ArraySlice<UInt8>`, and `String`.
///
/// Create an empty body:
/// ```swift
/// let body = HTTPBody()
/// ```
///
/// Create a body from a byte chunk:
/// ```swift
/// let bytes: ArraySlice<UInt8> = ...
/// let body = HTTPBody(bytes)
/// ```
///
/// Create a body from `Foundation.Data`:
/// ```swift
/// let data: Foundation.Data = ...
/// let body = HTTPBody(data)
/// ```
///
/// Create a body from a string:
/// ```swift
/// let body = HTTPBody("Hello, world!")
/// ```
///
/// ## Creating a body from an async sequence
/// The body type also supports initialization from an async sequence.
///
/// ```swift
/// let producingSequence = ... // an AsyncSequence
/// let length: HTTPBody.Length = .known(1024) // or .unknown
/// let body = HTTPBody(
///     producingSequence,
///     length: length,
///     iterationBehavior: .single // or .multiple
/// )
/// ```
///
/// In addition to the async sequence, also provide the total body length,
/// if known (this can be sent in the `content-length` header), and whether
/// the sequence is safe to be iterated multiple times, or can only be iterated
/// once.
///
/// Sequences that can be iterated multiple times work better when an HTTP
/// request needs to be retried, or if a redirect is encountered.
///
/// In addition to providing the async sequence, you can also produce the body
/// using an `AsyncStream` or `AsyncThrowingStream`:
///
/// ```swift
/// let body = HTTPBody(
///     AsyncStream(ArraySlice<UInt8>.self, { continuation in
///         continuation.yield([72, 69])
///         continuation.yield([76, 76, 79])
///         continuation.finish()
///     }),
///     length: .known(5)
/// )
/// ```
///
/// ## Consuming a body as an async sequence
/// The `HTTPBody` type conforms to `AsyncSequence` and uses `ArraySlice<UInt8>`
/// as its element type, so it can be consumed in a streaming fashion, without
/// ever buffering the whole body in your process.
///
/// For example, to get another sequence that contains only the size of each
/// chunk, and print each size, use:
///
/// ```swift
/// let chunkSizes = body.map { chunk in chunk.count }
/// for try await chunkSize in chunkSizes {
///     print("Chunk size: \(chunkSize)")
/// }
/// ```
///
/// ## Consuming a body as a buffer
/// If you need to collect the whole body before processing it, use one of
/// the convenience initializers on the target types that take an `HTTPBody`.
///
/// To get all the bytes, use the initializer on `ArraySlice<UInt8>` or `[UInt8]`:
///
/// ```swift
/// let buffer = try await ArraySlice(collecting: body, upTo: 2 * 1024 * 1024)
/// ```
///
/// The body type provides more variants of the collecting initializer on commonly
/// used buffers, such as:
/// - `Foundation.Data`
/// - `Swift.String`
///
/// > Important: You must provide the maximum number of bytes you can buffer in
/// memory, in the example above we provide 2 MB. If more bytes are available,
/// the method throws the `TooManyBytesError` to stop the process running out
/// of memory. While discouraged, you can provide `upTo: .max` to
/// read all the available bytes, without a limit.
public final class HTTPBody: @unchecked Sendable {

  /// The underlying byte chunk type.
  public typealias ByteChunk = ArraySlice<UInt8>

  /// The iteration behavior, which controls how many times
  /// the input sequence can be iterated.
  public let iterationBehavior: IterationBehavior

  /// Describes the total length of the body, in bytes, if known.
  public enum Length: Sendable, Equatable {

    /// Total length not known yet.
    case unknown

    /// Total length is known.
    case known(Int64)
  }

  /// The total length of the body, in bytes, if known.
  public let length: Length

  /// The underlying type-erased async sequence.
  private let sequence: AnySequence<ByteChunk>

  /// A lock for shared mutable state.
  private let lock: NSLock = {
    let lock = NSLock()
    lock.name = "com.apple.swift-openapi-generator.runtime.body"
    return lock
  }()

  /// A flag indicating whether an iterator has already been created.
  private var locked_iteratorCreated: Bool = false

  /// A flag indicating whether an iterator has already been created, only
  /// used for testing.
  internal var testing_iteratorCreated: Bool {
    lock.lock()
    defer { lock.unlock() }
    return locked_iteratorCreated
  }

  /// Tries to mark an iterator as created, verifying that it is allowed
  /// based on the values of `iterationBehavior` and `locked_iteratorCreated`.
  /// - Throws: If another iterator is not allowed to be created.
  private func tryToMarkIteratorCreated() throws {
    lock.lock()
    defer {
      locked_iteratorCreated = true
      lock.unlock()
    }
    guard iterationBehavior == .single else { return }
    if locked_iteratorCreated { throw TooManyIterationsError() }
  }

  /// Creates a new body.
  /// - Parameters:
  ///   - sequence: The input sequence providing the byte chunks.
  ///   - length: The total length of the body, in other words the accumulated
  ///     length of all the byte chunks.
  ///   - iterationBehavior: The sequence's iteration behavior, which
  ///     indicates whether the sequence can be iterated multiple times.
  @usableFromInline init(
    _ sequence: AnySequence<ByteChunk>,
    length: Length,
    iterationBehavior: IterationBehavior
  ) {
    self.sequence = sequence
    self.length = length
    self.iterationBehavior = iterationBehavior
  }

  /// Creates a new body with the provided sequence of byte chunks.
  /// - Parameters:
  ///   - byteChunks: A sequence of byte chunks.
  ///   - length: The total length of the body.
  ///   - iterationBehavior: The iteration behavior of the sequence, which
  ///     indicates whether it can be iterated multiple times.
  @usableFromInline convenience init(
    _ byteChunks: some Sequence<ByteChunk> & Sendable,
    length: Length,
    iterationBehavior: IterationBehavior
  ) {
    self.init(
      .init(WrappedSyncSequence(sequence: byteChunks)),
      length: length,
      iterationBehavior: iterationBehavior
    )
  }
}

extension HTTPBody: Equatable {
  /// Compares two HTTPBody instances for equality by comparing their object identifiers.
  ///
  /// - Parameters:
  ///   - lhs: The left-hand side HTTPBody.
  ///   - rhs: The right-hand side HTTPBody.
  ///
  /// - Returns: `true` if the object identifiers of the two HTTPBody instances are equal,
  /// indicating that they are the same object in memory; otherwise, returns `false`.
  public static func == (lhs: HTTPBody, rhs: HTTPBody) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

extension HTTPBody: Hashable {
  /// Hashes the HTTPBody instance by combining its object identifier into the provided hasher.
  ///
  /// - Parameter hasher: The hasher used to combine the hash value.
  public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

// MARK: - Creating the HTTPBody

extension HTTPBody {

  /// Creates a new empty body.
  @inlinable public convenience init() {
    self.init(.init(EmptySequence()), length: .known(0), iterationBehavior: .multiple)
  }

  /// Creates a new body with the provided byte chunk.
  /// - Parameters:
  ///   - bytes: A byte chunk.
  ///   - length: The total length of the body.
  @inlinable public convenience init(_ bytes: ByteChunk, length: Length) {
    self.init([bytes], length: length, iterationBehavior: .multiple)
  }

  /// Creates a new body with the provided byte chunk.
  /// - Parameter bytes: A byte chunk.
  @inlinable public convenience init(_ bytes: ByteChunk) {
    self.init([bytes], length: .known(Int64(bytes.count)), iterationBehavior: .multiple)
  }

  /// Creates a new body with the provided byte sequence.
  /// - Parameters:
  ///   - bytes: A byte chunk.
  ///   - length: The total length of the body.
  ///   - iterationBehavior: The iteration behavior of the sequence, which
  ///     indicates whether it can be iterated multiple times.
  @inlinable public convenience init(
    _ bytes: some Sequence<UInt8> & Sendable,
    length: Length,
    iterationBehavior: IterationBehavior
  ) { self.init([ArraySlice(bytes)], length: length, iterationBehavior: iterationBehavior) }

  /// Creates a new body with the provided byte collection.
  /// - Parameters:
  ///   - bytes: A byte chunk.
  ///   - length: The total length of the body.
  @inlinable public convenience init(_ bytes: some Collection<UInt8> & Sendable, length: Length) {
    self.init(ArraySlice(bytes), length: length, iterationBehavior: .multiple)
  }

  /// Creates a new body with the provided byte collection.
  /// - Parameter bytes: A byte chunk.
  @inlinable public convenience init(_ bytes: some Collection<UInt8> & Sendable) {
    self.init(bytes, length: .known(Int64(bytes.count)))
  }

  /// Creates a new body with the provided async throwing stream.
  /// - Parameters:
  ///   - stream: An async throwing stream that provides the byte chunks.
  ///   - length: The total length of the body.
  @inlinable public convenience init(
    _ stream: AsyncThrowingStream<ByteChunk, any Error>,
    length: HTTPBody.Length
  ) {
    self.init(.init(stream), length: length, iterationBehavior: .single)
  }

  /// Creates a new body with the provided async stream.
  /// - Parameters:
  ///   - stream: An async stream that provides the byte chunks.
  ///   - length: The total length of the body.
  @inlinable public convenience init(_ stream: AsyncStream<ByteChunk>, length: HTTPBody.Length) {
    self.init(.init(stream), length: length, iterationBehavior: .single)
  }

  /// Creates a new body with the provided async sequence.
  /// - Parameters:
  ///   - sequence: An async sequence that provides the byte chunks.
  ///   - length: The total length of the body.
  ///   - iterationBehavior: The iteration behavior of the sequence, which
  ///     indicates whether it can be iterated multiple times.
  @inlinable public convenience init<Bytes: AsyncSequence>(
    _ sequence: Bytes,
    length: HTTPBody.Length,
    iterationBehavior: IterationBehavior
  ) where Bytes.Element == ByteChunk, Bytes: Sendable {
    self.init(.init(sequence), length: length, iterationBehavior: iterationBehavior)
  }

  /// Creates a new body with the provided async sequence of byte sequences.
  /// - Parameters:
  ///   - sequence: An async sequence that provides the byte chunks.
  ///   - length: The total length of the body.
  ///   - iterationBehavior: The iteration behavior of the sequence, which
  ///     indicates whether it can be iterated multiple times.
  @inlinable public convenience init<Bytes: AsyncSequence>(
    _ sequence: Bytes,
    length: HTTPBody.Length,
    iterationBehavior: IterationBehavior
  ) where Bytes: Sendable, Bytes.Element: Sequence & Sendable, Bytes.Element.Element == UInt8 {
    self.init(
      sequence.map { ArraySlice($0) },
      length: length,
      iterationBehavior: iterationBehavior
    )
  }
}

// MARK: - Consuming the body

extension HTTPBody: AsyncSequence {
  /// Represents a single element within an asynchronous sequence
  public typealias Element = ByteChunk
  /// Represents an asynchronous iterator over a sequence of elements.
  public typealias AsyncIterator = Iterator
  /// Creates and returns an asynchronous iterator
  ///
  /// - Returns: An asynchronous iterator for byte chunks.
  /// - Note: The returned sequence throws an error if no further iterations are allowed. See ``IterationBehavior``.
  public func makeAsyncIterator() -> AsyncIterator {
    do {
      try tryToMarkIteratorCreated()
      return .init(sequence.makeAsyncIterator())
    } catch { return .init(throwing: error) }
  }
}

extension HTTPBody {

  /// An error thrown by the collecting initializer when the body contains more
  /// than the maximum allowed number of bytes.
  private struct TooManyBytesError: Error, CustomStringConvertible, LocalizedError {

    /// The maximum number of bytes acceptable by the user.
    let maxBytes: Int

    var description: String {
      "OpenAPIRuntime.HTTPBody contains more than the maximum allowed \(maxBytes) bytes."
    }

    var errorDescription: String? { description }
  }

  /// An error thrown by the collecting initializer when another iteration of
  /// the body is not allowed.
  private struct TooManyIterationsError: Error, CustomStringConvertible, LocalizedError {

    var description: String {
      "OpenAPIRuntime.HTTPBody attempted to create a second iterator, but the underlying sequence is only safe to be iterated once."
    }

    var errorDescription: String? { description }
  }

  /// Accumulates the full body in-memory into a single buffer
  /// up to the provided maximum number of bytes and returns it.
  /// - Parameter maxBytes: The maximum number of bytes this method is allowed
  ///     to accumulate in memory before it throws an error.
  /// - Throws: `TooManyBytesError` if the body contains more
  ///   than `maxBytes`.
  /// - Returns: A byte chunk containing all the accumulated bytes.
  fileprivate func collect(upTo maxBytes: Int) async throws -> ByteChunk {
    // If the length is known, verify it's within the limit.
    if case .known(let knownBytes) = length {
      guard knownBytes <= maxBytes else { throw TooManyBytesError(maxBytes: maxBytes) }
    }

    // Accumulate the byte chunks.
    var buffer = ByteChunk()
    for try await chunk in self {
      guard buffer.count + chunk.count <= maxBytes else {
        throw TooManyBytesError(maxBytes: maxBytes)
      }
      buffer.append(contentsOf: chunk)
    }
    return buffer
  }
}

extension HTTPBody.ByteChunk {
  /// Creates a byte chunk by accumulating the full body in-memory into a single buffer
  /// up to the provided maximum number of bytes and returning it.
  /// - Parameters:
  ///   - body: The HTTP body to collect.
  ///   - maxBytes: The maximum number of bytes this method is allowed
  ///     to accumulate in memory before it throws an error.
  /// - Throws: `TooManyBytesError` if the body contains more
  ///   than `maxBytes`.
  public init(collecting body: HTTPBody, upTo maxBytes: Int) async throws {
    self = try await body.collect(upTo: maxBytes)
  }
}

extension Array where Element == UInt8 {
  /// Creates a byte array by accumulating the full body in-memory into a single buffer
  /// up to the provided maximum number of bytes and returning it.
  /// - Parameters:
  ///   - body: The HTTP body to collect.
  ///   - maxBytes: The maximum number of bytes this method is allowed
  ///     to accumulate in memory before it throws an error.
  /// - Throws: `TooManyBytesError` if the body contains more
  ///   than `maxBytes`.
  public init(collecting body: HTTPBody, upTo maxBytes: Int) async throws {
    self = try await Array(body.collect(upTo: maxBytes))
  }
}

// MARK: - String-based bodies

extension HTTPBody {

  /// Creates a new body with the provided string encoded as UTF-8 bytes.
  /// - Parameters:
  ///   - string: A string to encode as bytes.
  ///   - length: The total length of the body.
  @inlinable public convenience init(_ string: some StringProtocol & Sendable, length: Length) {
    self.init(ByteChunk(string), length: length)
  }

  /// Creates a new body with the provided string encoded as UTF-8 bytes.
  /// - Parameter string: A string to encode as bytes.
  @inlinable public convenience init(_ string: some StringProtocol & Sendable) {
    self.init(ByteChunk(string))
  }

  /// Creates a new body with the provided async throwing stream of strings.
  /// - Parameters:
  ///   - stream: An async throwing stream that provides the string chunks.
  ///   - length: The total length of the body.
  @inlinable public convenience init(
    _ stream: AsyncThrowingStream<some StringProtocol & Sendable, any Error & Sendable>,
    length: HTTPBody.Length
  ) {
    self.init(
      .init(stream.map { ByteChunk.init($0) }),
      length: length,
      iterationBehavior: .single
    )
  }

  /// Creates a new body with the provided async stream of strings.
  /// - Parameters:
  ///   - stream: An async stream that provides the string chunks.
  ///   - length: The total length of the body.
  @inlinable public convenience init(
    _ stream: AsyncStream<some StringProtocol & Sendable>,
    length: HTTPBody.Length
  ) {
    self.init(
      .init(stream.map { ByteChunk.init($0) }),
      length: length,
      iterationBehavior: .single
    )
  }

  /// Creates a new body with the provided async sequence of string chunks.
  /// - Parameters:
  ///   - sequence: An async sequence that provides the string chunks.
  ///   - length: The total length of the body.
  ///   - iterationBehavior: The iteration behavior of the sequence, which
  ///     indicates whether it can be iterated multiple times.
  @inlinable public convenience init<Strings: AsyncSequence>(
    _ sequence: Strings,
    length: HTTPBody.Length,
    iterationBehavior: IterationBehavior
  ) where Strings.Element: StringProtocol & Sendable, Strings: Sendable {
    self.init(
      .init(sequence.map { ByteChunk.init($0) }),
      length: length,
      iterationBehavior: iterationBehavior
    )
  }
}

extension HTTPBody.ByteChunk {

  /// Creates a byte chunk compatible with the `HTTPBody` type from the provided string.
  /// - Parameter string: The string to encode.
  @inlinable init(_ string: some StringProtocol & Sendable) { self = Array(string.utf8)[...] }
}

extension String {
  /// Creates a string by accumulating the full body in-memory into a single buffer up to
  /// the provided maximum number of bytes, converting it to string using UTF-8 encoding.
  /// - Parameters:
  ///   - body: The HTTP body to collect.
  ///   - maxBytes: The maximum number of bytes this method is allowed
  ///     to accumulate in memory before it throws an error.
  /// - Throws: `TooManyBytesError` if the body contains more
  ///   than `maxBytes`.
  public init(collecting body: HTTPBody, upTo maxBytes: Int) async throws {
    self = try await String(decoding: body.collect(upTo: maxBytes), as: UTF8.self)
  }
}

// MARK: - HTTPBody conversions

extension HTTPBody: ExpressibleByStringLiteral {
  /// Initializes an `HTTPBody` instance with the provided string value.
  ///
  /// - Parameter value: The string literal to use for initializing the `HTTPBody`.
  public convenience init(stringLiteral value: String) { self.init(value) }
}

extension HTTPBody {

  /// Creates a new body from the provided array of bytes.
  /// - Parameter bytes: An array of bytes.
  @inlinable public convenience init(_ bytes: [UInt8]) { self.init(bytes[...]) }
}

extension HTTPBody: ExpressibleByArrayLiteral {
  /// Element type for array literals.
  public typealias ArrayLiteralElement = UInt8
  /// Initializes an `HTTPBody` instance with a sequence of `UInt8` elements.
  ///
  /// - Parameter elements: A variadic list of `UInt8` elements used to initialize the `HTTPBody`.
  public convenience init(arrayLiteral elements: UInt8...) { self.init(elements) }
}

extension HTTPBody {

  /// Creates a new body from the provided data chunk.
  /// - Parameter data: A single data chunk.
  public convenience init(_ data: Data) { self.init(ArraySlice(data)) }
}

extension Data {
  /// Creates a Data by accumulating the full body in-memory into a single buffer up to
  /// the provided maximum number of bytes and converting it to `Data`.
  /// - Parameters:
  ///   - body: The HTTP body to collect.
  ///   - maxBytes: The maximum number of bytes this method is allowed
  ///     to accumulate in memory before it throws an error.
  /// - Throws: `TooManyBytesError` if the body contains more
  ///   than `maxBytes`.
  public init(collecting body: HTTPBody, upTo maxBytes: Int) async throws {
    self = try await Data(body.collect(upTo: maxBytes))
  }
}

// MARK: - Underlying async sequences

extension HTTPBody {

  /// An async iterator of both input async sequences and of the body itself.
  public struct Iterator: AsyncIteratorProtocol {

    /// The element byte chunk type.
    public typealias Element = HTTPBody.ByteChunk

    /// The closure that produces the next element.
    private let produceNext: () async throws -> Element?

    /// Creates a new type-erased iterator from the provided iterator.
    /// - Parameter iterator: The iterator to type-erase.
    @usableFromInline init<Iterator: AsyncIteratorProtocol>(_ iterator: Iterator)
    where Iterator.Element == Element {
      var iterator = iterator
      self.produceNext = { try await iterator.next() }
    }
    /// Creates an iterator throwing the given error when iterated.
    /// - Parameter error: The error to throw on iteration.
    fileprivate init(throwing error: any Error) { self.produceNext = { throw error } }

    /// Advances the iterator to the next element and returns it asynchronously.
    ///
    /// - Returns: The next element in the sequence, or `nil` if there are no more elements.
    /// - Throws: An error if there is an issue advancing the iterator or retrieving the next element.
    public mutating func next() async throws -> Element? { try await produceNext() }
  }
}
