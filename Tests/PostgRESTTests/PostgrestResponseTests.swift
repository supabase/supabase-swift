import Foundation
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestResponseTests {
  @Test
  func initWithCount() {
    // Prepare data and response
    let data = Data()
    let response = HTTPURLResponse(
      url: URL(string: "http://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Range": "bytes 0-100/200"]
    )!
    let value = "Test Value"

    // Create the PostgrestResponse instance
    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    // Assert the properties
    #expect(postgrestResponse.data == data)
    #expect(postgrestResponse.response == response)
    #expect(postgrestResponse.value == value)
    #expect(postgrestResponse.status == 200)
    #expect(postgrestResponse.count == 200)
  }

  @Test
  func initWithNoCount() {
    // Prepare data and response
    let data = Data()
    let response = HTTPURLResponse(
      url: URL(string: "http://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Range": "*"]
    )!
    let value = "Test Value"

    // Create the PostgrestResponse instance
    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    // Assert the properties
    #expect(postgrestResponse.data == data)
    #expect(postgrestResponse.response == response)
    #expect(postgrestResponse.value == value)
    #expect(postgrestResponse.status == 200)
    #expect(postgrestResponse.count == nil)
  }
}
