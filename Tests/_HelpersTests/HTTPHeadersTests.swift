//
//  HTTPHeadersTests.swift
//
//
//  Created by Guilherme Souza on 24/04/24.
//

@testable import _Helpers
import XCTest

final class HTTPHeadersTests: XCTestCase {
  func testInitWithDictionary() {
    let headers = HTTPHeaders(["Content-Type": "application/json"])
    XCTAssertEqual(headers["content-type"], "application/json")
  }

  func testUpdate() {
    var headers = HTTPHeaders()
    headers.update(name: "Content-Type", value: "application/json")
    XCTAssertEqual(headers["content-type"], "application/json")
  }

  func testRemove() {
    var headers = HTTPHeaders(["Content-Type": "application/json"])
    headers.remove(name: "Content-Type")
    XCTAssertNil(headers["content-type"])
  }

  func testValueForName() {
    let headers = HTTPHeaders(["Content-Type": "application/json"])
    XCTAssertEqual(headers.value(for: "Content-Type"), "application/json")
  }

  func testSubscript() {
    var headers = HTTPHeaders(["Content-Type": "application/json"])
    headers["Content-Type"] = "text/html"
    XCTAssertEqual(headers["content-type"], "text/html")
  }

  func testDictionary() {
    let headers = HTTPHeaders(["Content-Type": "application/json"])
    XCTAssertEqual(headers.dictionary, ["Content-Type": "application/json"])
  }

  func testMerge() {
    var headers1 = HTTPHeaders(["Content-Type": "application/json"])
    let headers2 = HTTPHeaders(["Accept": "application/json"])
    headers1.merge(with: headers2)
    XCTAssertEqual(headers1.dictionary, ["Content-Type": "application/json", "Accept": "application/json"])
  }

  func testMerged() {
    let headers1 = HTTPHeaders(["Content-Type": "application/json"])
    let headers2 = HTTPHeaders(["Accept": "application/json"])
    let mergedHeaders = headers1.merged(with: headers2)
    XCTAssertEqual(mergedHeaders.dictionary, ["Content-Type": "application/json", "Accept": "application/json"])
  }
}

final class HTTPHeaderTests: XCTestCase {
  func testInit() {
    let header = HTTPHeader(name: "Content-Type", value: "application/json")
    XCTAssertEqual(header.name, "Content-Type")
    XCTAssertEqual(header.value, "application/json")
  }

  func testDescription() {
    let header = HTTPHeader(name: "Content-Type", value: "application/json")
    XCTAssertEqual(header.description, "Content-Type: application/json")
  }
}
