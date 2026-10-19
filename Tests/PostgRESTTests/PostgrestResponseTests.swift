import Foundation
import HTTPTypes
import Testing

@testable import PostgREST

@Suite
struct PostgrestResponseTests {
  @Test
  func initWithCount() {
    let data = Data()
    let response = HTTPResponse(status: .ok, headerFields: [.contentRange: "bytes 0-100/200"])
    let value = "Test Value"

    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    #expect(postgrestResponse.data == data)
    #expect(postgrestResponse.response == response)
    #expect(postgrestResponse.value == value)
    #expect(postgrestResponse.status == 200)
    #expect(postgrestResponse.count == 200)
  }

  @Test
  func initWithNoCount() {
    let data = Data()
    let response = HTTPResponse(status: .ok, headerFields: [.contentRange: "*"])
    let value = "Test Value"

    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    #expect(postgrestResponse.data == data)
    #expect(postgrestResponse.response == response)
    #expect(postgrestResponse.value == value)
    #expect(postgrestResponse.status == 200)
    #expect(postgrestResponse.count == nil)
  }
}
