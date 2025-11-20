//
//  HTTPErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Helpers
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class HTTPErrorTests: XCTestCase {

  func testInitialization() {
    let data = Data("test error message".utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 400,
      httpVersion: "1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(error.data, data)
    XCTAssertEqual(error.response, response)
  }

  func testLocalizedErrorDescription_WithUTF8Data() {
    let data = Data("Bad Request: Invalid parameters".utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 400,
      httpVersion: "1.1",
      headerFields: nil
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(
      error.errorDescription,
      "Status Code: 400 Body: Bad Request: Invalid parameters"
    )
  }

  func testLocalizedErrorDescription_WithEmptyData() {
    let data = Data()
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 404,
      httpVersion: "1.1",
      headerFields: nil
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(error.errorDescription, "Status Code: 404 Body: ")
  }

  func testLocalizedErrorDescription_WithNonUTF8Data() {
    // Create data that can't be converted to UTF-8 string
    let bytes: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC]
    let data = Data(bytes)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 500,
      httpVersion: "1.1",
      headerFields: nil
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(error.errorDescription, "Status Code: 500")
  }

  func testLocalizedErrorDescription_WithJSONData() {
    let jsonString = """
      {
        "error": "Validation failed",
        "details": "Email format is invalid"
      }
      """
    let data = Data(jsonString.utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 422,
      httpVersion: "1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(
      error.errorDescription,
      "Status Code: 422 Body: \(jsonString)"
    )
  }

  func testLocalizedErrorDescription_WithSpecialCharacters() {
    let message = "Error with special chars: áéíóú ñ ç"
    let data = Data(message.utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 400,
      httpVersion: "1.1",
      headerFields: nil
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(
      error.errorDescription,
      "Status Code: 400 Body: \(message)"
    )
  }

  func testLocalizedErrorDescription_WithLargeData() {
    let largeMessage = String(repeating: "A", count: 1000)
    let data = Data(largeMessage.utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 413,
      httpVersion: "1.1",
      headerFields: nil
    )!

    let error = HTTPError(data: data, response: response)

    XCTAssertEqual(
      error.errorDescription,
      "Status Code: 413 Body: \(largeMessage)"
    )
  }

  func testProperties() {
    let data = Data("test error".utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 400,
      httpVersion: "1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    let error = HTTPError(data: data, response: response)

    // Test that properties are correctly set
    XCTAssertEqual(error.data, data)
    XCTAssertEqual(error.response, response)
    XCTAssertEqual(error.response.statusCode, 400)
    XCTAssertEqual(error.response.url, URL(string: "https://example.com")!)
  }
}
