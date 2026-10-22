import Foundation
import HTTPTypes
import Testing

@testable import Functions

@Suite
struct FunctionInvokeOptionsTests {
  @Test
  func defaults() {
    let options = FunctionInvokeOptions()

    #expect(options.method == .post)
    #expect(options.headers == [:])
    #expect(options.query == [])
    #expect(options.region == nil)
    #expect(options.timeout == nil)
  }

  @Test
  func isHashable() {
    let a = FunctionInvokeOptions(
      method: .get, headers: [.contentType: "text/plain"], region: .usEast1)
    let b = FunctionInvokeOptions(
      method: .get, headers: [.contentType: "text/plain"], region: .usEast1)

    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
    #expect(a != FunctionInvokeOptions())
  }
}
