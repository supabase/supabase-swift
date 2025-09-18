import Alamofire
import Foundation
import Testing

@testable import Functions

@Suite struct FunctionInvokeOptionsTests {
  @Test("Initialize with string body sets correct content type")
  func initWithStringBody() {
    var options = FunctionInvokeOptions()
    options.setBody("string value")
    #expect(options.headers["Content-Type"] == "text/plain")
  }

  @Test("Initialize with data body sets correct content type")
  func initWithDataBody() {
    let bodyData = "binary value".data(using: .utf8)!
    var options = FunctionInvokeOptions()
    options.setBody(bodyData)
    #expect(options.headers["Content-Type"] == "application/octet-stream")
  }

  @Test("Initialize with encodable body sets correct content type")
  func initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    var options = FunctionInvokeOptions()
    options.setBody(Body(value: "value"))
    #expect(options.headers["Content-Type"] == "application/json")
  }

  @Test("Initialize with custom content type preserves custom header")
  func initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let bodyData = "binary value".data(using: .utf8)!
    var options = FunctionInvokeOptions()
    options.setBody(bodyData)
    options.headers["Content-Type"] = contentType
    #expect(options.headers["Content-Type"] == contentType)
  }

  @Test("HTTP method is set correctly", arguments: [HTTPMethod.get, .post, .put, .patch, .delete])
  func testMethod(method: HTTPMethod) {
    let options = FunctionInvokeOptions(method: method)
    #expect(options.method == method)
  }
}
