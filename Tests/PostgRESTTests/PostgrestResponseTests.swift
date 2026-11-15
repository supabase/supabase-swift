import Foundation
import HTTPTypes
import Testing

@testable import PostgREST

@Suite
struct PostgrestResponseTests {
  @Test
  func initFromHeadCopiesStatusHeadersAndBody() {
    let head = HTTPResponse(
      status: .partialContent,
      headerFields: [.contentRange: "0-99/200", .sbRequestID: "req-1"])

    let response = PostgrestResponse(head, body: Data("[]".utf8), value: "Test Value")

    #expect(response.status == .partialContent)
    #expect(response.headers == head.headerFields)
    #expect(response.body == Data("[]".utf8))
    #expect(response.value == "Test Value")
    #expect(response.requestID == "req-1")
  }

  @Test
  func initFromHeadReadsTheCountFromContentRange() {
    let head = HTTPResponse(status: .ok, headerFields: [.contentRange: "0-100/200"])

    #expect(PostgrestResponse(head, body: Data(), value: ()).count == 200)
  }

  @Test
  func initFromHeadHasNoCountForAnUnknownTotal() {
    let head = HTTPResponse(status: .ok, headerFields: [.contentRange: "*/*"])

    #expect(PostgrestResponse(head, body: Data(), value: ()).count == nil)
  }

  @Test
  func initFromHeadHasNoCountWithoutContentRange() {
    let head = HTTPResponse(status: .ok)

    #expect(PostgrestResponse(head, body: Data(), value: ()).count == nil)
  }
}
