//
//  PaginationLinksTests.swift
//
//
//  Created by Ranbir Singh on 22/09/26.
//

import Testing

@testable import Auth

@Suite
struct PaginationLinksTests {

  @Test
  func readsThePageOfEveryRelation() {
    let pages = parsePaginationLinks(
      "</admin/users?page=2&per_page=50>; rel=\"next\", "
        + "</admin/users?page=5&per_page=50>; rel=\"last\""
    )

    #expect(pages == ["next": 2, "last": 5])
  }

  @Test
  func readsThePageWhenItIsNotTheFirstQueryItem() {
    let pages = parsePaginationLinks("</admin/users?per_page=50&page=2>; rel=\"next\"")

    #expect(pages == ["next": 2])
  }

  @Test
  func returnsNoPagesForAMissingHeader() {
    #expect(parsePaginationLinks(nil).isEmpty)
  }

  @Test
  func returnsNoPagesForAnEmptyHeader() {
    #expect(parsePaginationLinks("").isEmpty)
  }

  @Test
  func skipsALinkWithoutAQueryString() {
    #expect(parsePaginationLinks("</admin/users>; rel=\"next\"").isEmpty)
  }

  @Test
  func skipsALinkWithoutAPageQueryItem() {
    #expect(parsePaginationLinks("</admin/users?per_page=50>; rel=\"next\"").isEmpty)
  }

  @Test
  func skipsALinkWhosePageIsNotANumber() {
    #expect(parsePaginationLinks("</admin/users?page=last>; rel=\"next\"").isEmpty)
  }

  @Test
  func skipsAHeaderThatCarriesNoLink() {
    #expect(parsePaginationLinks("rel=\"next\"").isEmpty)
  }
}
