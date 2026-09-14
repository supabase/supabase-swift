//
//  HTTPErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import HTTPTypes
import Helpers
import Testing

@Suite
struct HTTPErrorTests {

  @Test
  func initialization() {
    let data = Data("test error message".utf8)
    let response = HTTPResponse(
      status: .badRequest, headerFields: [.contentType: "application/json"])

    let error = HTTPError(data: data, response: response)

    #expect(error.data == data)
    #expect(error.response == response)
  }

  @Test
  func localizedErrorDescription_WithUTF8Data() {
    let data = Data("Bad Request: Invalid parameters".utf8)
    let error = HTTPError(data: data, response: HTTPResponse(status: .badRequest))

    #expect(
      error.errorDescription
        == "Status Code: 400 Body: Bad Request: Invalid parameters"
    )
  }

  @Test
  func localizedErrorDescription_WithEmptyData() {
    let error = HTTPError(data: Data(), response: HTTPResponse(status: .notFound))

    #expect(error.errorDescription == "Status Code: 404 Body: ")
  }

  @Test
  func localizedErrorDescription_WithNonUTF8Data() {
    // Create data that can't be converted to UTF-8 string
    let bytes: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC]
    let data = Data(bytes)
    let error = HTTPError(data: data, response: HTTPResponse(status: .internalServerError))

    #expect(error.errorDescription == "Status Code: 500")
  }

  @Test
  func localizedErrorDescription_WithJSONData() {
    let jsonString = """
      {
        "error": "Validation failed",
        "details": "Email format is invalid"
      }
      """
    let data = Data(jsonString.utf8)
    let response = HTTPResponse(
      status: .unprocessableContent, headerFields: [.contentType: "application/json"])

    let error = HTTPError(data: data, response: response)

    #expect(
      error.errorDescription
        == "Status Code: 422 Body: \(jsonString)"
    )
  }

  @Test
  func localizedErrorDescription_WithSpecialCharacters() {
    let message = "Error with special chars: áéíóú ñ ç"
    let data = Data(message.utf8)
    let error = HTTPError(data: data, response: HTTPResponse(status: .badRequest))

    #expect(
      error.errorDescription
        == "Status Code: 400 Body: \(message)"
    )
  }

  @Test
  func localizedErrorDescription_WithLargeData() {
    let largeMessage = String(repeating: "A", count: 1000)
    let data = Data(largeMessage.utf8)
    let error = HTTPError(data: data, response: HTTPResponse(status: .contentTooLarge))

    #expect(
      error.errorDescription
        == "Status Code: 413 Body: \(largeMessage)"
    )
  }

  @Test
  func properties() {
    let data = Data("test error".utf8)
    let response = HTTPResponse(
      status: .badRequest, headerFields: [.contentType: "application/json"])

    let error = HTTPError(data: data, response: response)

    // Test that properties are correctly set
    #expect(error.data == data)
    #expect(error.response == response)
    #expect(error.response.status.code == 400)
    #expect(error.response.headerFields[.contentType] == "application/json")
  }
}
