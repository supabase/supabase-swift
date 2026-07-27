import Foundation
import HTTPTypes
import Testing

@testable import Functions

@Suite
struct FunctionInvokeOptionsTests {
  @Test
  func initWithStringBody() {
    let options = FunctionInvokeOptions(body: "string value")
    #expect(options.headers[.contentType] == "text/plain")
    #expect(options.body != nil)
  }

  @Test
  func initWithDataBody() {
    let options = FunctionInvokeOptions(body: "binary value".data(using: .utf8)!)
    #expect(options.headers[.contentType] == "application/octet-stream")
    #expect(options.body != nil)
  }

  @Test
  func initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    let options = FunctionInvokeOptions(body: Body(value: "value"))
    #expect(options.headers[.contentType] == "application/json")
    #expect(options.body != nil)
  }

  @Test
  func initWithEncodableBodyAndCustomEncoder() {
    struct Body: Encodable {
      let userName: String
    }

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let options = FunctionInvokeOptions(body: Body(userName: "test"), encoder: encoder)
    #expect(options.headers[.contentType] == "application/json")

    let json = try! JSONSerialization.jsonObject(with: options.body!) as! [String: Any]
    #expect(json["user_name"] != nil)
    #expect(json["userName"] == nil)
  }

  @Test
  func initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let options = FunctionInvokeOptions(
      headers: ["Content-Type": contentType],
      body: "binary value".data(using: .utf8)!
    )
    #expect(options.headers[.contentType] == contentType)
    #expect(options.body != nil)
  }

  @Test
  func method() {
    let testCases: [FunctionInvokeOptions.Method: HTTPTypes.HTTPRequest.Method] = [
      .get: .get,
      .post: .post,
      .put: .put,
      .patch: .patch,
      .delete: .delete,
    ]

    for (method, expected) in testCases {
      #expect(FunctionInvokeOptions.httpMethod(method) == expected)
    }
  }
}
