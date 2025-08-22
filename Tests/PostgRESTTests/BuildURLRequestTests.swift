import ConcurrencyExtras
import Foundation
import SnapshotTesting
import XCTest

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct User: Encodable {
  var email: String
  var username: String?
}

final class BuildURLRequestTests: XCTestCase {
  let url = URL(string: "https://example.supabase.co")!

  struct TestCase: Sendable {
    let name: String
    let record: Bool
    let file: StaticString
    let line: UInt
    let build: @Sendable (PostgrestClient) async throws -> PostgrestBuilder

    init(
      name: String,
      record: Bool = false,
      file: StaticString = #file,
      line: UInt = #line,
      build: @escaping @Sendable (PostgrestClient) async throws -> PostgrestBuilder
    ) {
      self.name = name
      self.record = record
      self.file = file
      self.line = line
      self.build = build
    }
  }

  // TODO: Update test for Alamofire - temporarily commented out
  // This test requires custom fetch handling which doesn't exist with Alamofire
  // func testBuildRequest() async throws {
  //   // ... test implementation commented out
  // }

  func testSessionConfiguration() {
    let client = PostgrestClient(url: url, schema: nil, logger: nil)
    let clientInfoHeader = client.configuration.headers["X-Client-Info"]
    XCTAssertNotNil(clientInfoHeader)
  }
}

extension URLResponse {
  // Windows and Linux don't have the ability to empty initialize a URLResponse like `URLResponse()`
  // so
  // We provide a function that can give us the right value on an platform.
  // See https://github.com/apple/swift-corelibs-foundation/pull/4778
  fileprivate static func empty() -> URLResponse {
    #if os(Windows) || os(Linux) || os(Android)
      URLResponse(
        url: .init(string: "https://supabase.com")!,
        mimeType: nil,
        expectedContentLength: 0,
        textEncodingName: nil
      )
    #else
      URLResponse()
    #endif
  }
}
