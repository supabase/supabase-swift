//
//  PageSequenceTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 06/11/26.
//

import ConcurrencyExtras
import TestHelpers
import Testing

@testable import Helpers

@Suite
struct PageSequenceTests {
  struct Page: Sendable, Equatable {
    var items: [Int]
    var next: String?
  }

  struct Failure: Error {}

  /// A sequence over `pages`, keyed by cursor: the first page has cursor `nil`, page `n` has
  /// cursor `"\(n)"`. Records each cursor it is asked for.
  static func makeSequence(
    _ pages: [Page],
    requested: LockIsolated<[String?]> = .init([]),
    failAt: Int? = nil
  ) -> PageSequence<Int, Page, String> {
    PageSequence(
      fetch: { cursor in
        requested.withValue { $0.append(cursor) }
        let index = cursor.flatMap(Int.init) ?? 0
        if index == failAt { throw Failure() }
        return pages[index]
      },
      nextCursor: \.next,
      elements: \.items
    )
  }

  static let threePages = [
    Page(items: [1, 2], next: "1"),
    Page(items: [], next: "2"),
    Page(items: [3], next: nil),
  ]

  @Test
  func iteratesElementsOfEveryPageInOrder() async throws {
    let requested = LockIsolated<[String?]>([])
    let elements = try await Self.makeSequence(Self.threePages, requested: requested).collect()

    #expect(elements == [1, 2, 3])
    #expect(requested.value == [nil, "1", "2"])
  }

  @Test
  func pagesYieldsEveryPageIncludingEmptyOnes() async throws {
    let pages = try await Self.makeSequence(Self.threePages).pages.collect()

    #expect(pages == Self.threePages)
  }

  @Test
  func pageAfterFetchesOnePageForTheCursor() async throws {
    let requested = LockIsolated<[String?]>([])
    let sequence = Self.makeSequence(Self.threePages, requested: requested)

    #expect(try await sequence.page() == Self.threePages[0])
    #expect(try await sequence.page(after: "2") == Self.threePages[2])
    #expect(requested.value == [nil, "2"])
  }

  @Test
  func stoppingEarlyFetchesNoFurtherPages() async throws {
    let requested = LockIsolated<[String?]>([])
    for try await element in Self.makeSequence(Self.threePages, requested: requested) {
      #expect(element == 1)
      break
    }

    #expect(requested.value == [nil])
  }

  @Test
  func errorEndsIterationAfterTheElementsBeforeIt() async throws {
    var elements: [Int] = []
    await #expect(throws: Failure.self) {
      for try await element in Self.makeSequence(Self.threePages, failAt: 1) {
        elements.append(element)
      }
    }

    #expect(elements == [1, 2])
  }

  @Test
  func iteratorReturnsNilAfterTheLastPage() async throws {
    let requested = LockIsolated<[String?]>([])
    var iterator = Self.makeSequence([Page(items: [7], next: nil)], requested: requested)
      .makeAsyncIterator()

    #expect(try await iterator.next() == 7)
    #expect(try await iterator.next() == nil)
    #expect(try await iterator.next() == nil)
    #expect(requested.value == [nil])
  }

  @Test
  func eachIterationStartsFromTheFirstPage() async throws {
    let requested = LockIsolated<[String?]>([])
    let sequence = Self.makeSequence(Self.threePages, requested: requested)
    for try await _ in sequence.pages {}
    for try await _ in sequence.pages {}

    #expect(requested.value == [nil, "1", "2", nil, "1", "2"])
  }
}
