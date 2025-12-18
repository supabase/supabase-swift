import Foundation
import HTTPClient
import HTTPTypes
import Testing

@testable import Functions

@Suite
struct InvokeOptionsTests {
  @Test
  func bodyEncodable_setsJSONContentTypeWhenMissing() throws {
    struct Payload: Encodable { let value: Int }

    var options = FunctionsClient.InvokeOptions()
    try options.body(encodable: Payload(value: 1))

    #expect(options._body != nil)
    #expect(options.headers[.contentType] == "application/json")
  }

  @Test
  func bodyEncodable_doesNotOverrideExistingContentType() throws {
    struct Payload: Encodable { let value: Int }

    var options = FunctionsClient.InvokeOptions()
    options.headers[.contentType] = "application/vnd.test+json"
    try options.body(encodable: Payload(value: 1))

    #expect(options.headers[.contentType] == "application/vnd.test+json")
  }

  @Test
  func bodyString_setsTextPlainContentTypeWhenMissing() {
    var options = FunctionsClient.InvokeOptions()
    options.body(string: "hello")

    #expect(options._body != nil)
    #expect(options.headers[.contentType] == "text/plain")
  }

  @Test
  func bodyData_setsOctetStreamContentTypeWhenMissing() {
    var options = FunctionsClient.InvokeOptions()
    options.body(data: Data([0x01, 0x02]))

    #expect(options._body != nil)
    #expect(options.headers[.contentType] == "application/octet-stream")
  }

  @Test
  func bodyRaw_doesNotImplicitlySetContentType() {
    var options = FunctionsClient.InvokeOptions()
    options.body(HTTPBody(Data("hello".utf8)))

    #expect(options._body != nil)
    #expect(options.headers[.contentType] == nil)
  }

  @Test
  func bodyMultipart_setsMultipartState() {
    var options = FunctionsClient.InvokeOptions()
    let form = MultipartFormData(boundary: "b")
    form.append(Data("x".utf8), withName: "file")
    options.body(multipartFormData: form)

    #expect(options._multipartFormData != nil)
    #expect(options._body == nil)
  }

  @Test
  func defaults_arePostAndEmptyHeadersQueryRegion() {
    let options = FunctionsClient.InvokeOptions()
    #expect(options.method == .post)
    #expect(options.headers.isEmpty == true)
    #expect(options.query.isEmpty == true)
    #expect(options.region == nil)
  }
}

