//
//  FunctionsIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 04/08/25.
//

import Supabase
import XCTest

final class FunctionsIntegrationTests: XCTestCase {
  let client = SupabaseClient(
    supabaseURL: URL(string: DotEnv.SUPABASE_URL) ?? URL(string: "http://127.0.0.1:54321")!,
    supabaseKey: DotEnv.SUPABASE_ANON_KEY
  )

  func testInvokeMirror() async throws {
    let response: MirrorResponse = try await client.functions.invoke("mirror")
    XCTAssertTrue(response.url.contains("/mirror"))
    XCTAssertEqual(response.method, "POST")
  }

  func testInvokeMirrorWithClientHeader() async throws {
    let client = FunctionsClient(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/functions/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_ANON_KEY)",
        "CustomHeader": "check me",
      ]
    )
    let response: MirrorResponse = try await client.invoke("mirror")
    XCTAssertEqual(response.headersDictionary["customheader"], "check me")
  }

  func testInvokeMirrorWithInvokeHeader() async throws {
    let response: MirrorResponse = try await client.functions.invoke(
      "mirror",
      options: FunctionInvokeOptions(headers: ["Custom-Header": "check me"])
    )
    XCTAssertEqual(response.headersDictionary["custom-header"], "check me")
  }

  func testInvokeMirrorSetValidRegionOnRequest() async throws {
    let response: MirrorResponse = try await client.functions.invoke(
      "mirror",
      options: FunctionInvokeOptions(region: .apNortheast1)
    )
    XCTAssertEqual(response.headersDictionary["x-region"], "ap-northeast-1")
    XCTAssertTrue(response.url.contains("forceFunctionRegion=ap-northeast-1"))
  }

  func testInvokeWithRegionOverridesRegionInTheClinet() async throws {
    let client = FunctionsClient(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/functions/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_ANON_KEY)",
        "CustomHeader": "check me",
      ],
      region: .apNortheast1
    )
    let response: MirrorResponse = try await client.invoke(
      "mirror",
      options: FunctionInvokeOptions(region: .apSoutheast1)
    )
    XCTAssertEqual(response.headersDictionary["x-region"], "ap-southeast-1")
    XCTAssertTrue(response.url.contains("forceFunctionRegion=ap-southeast-1"))
  }

  func testStartClientWithDefaultRegionInvokeRevertsToAny() async throws {
    let client = FunctionsClient(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/functions/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_ANON_KEY)",
        "CustomHeader": "check me",
      ],
      region: .apSoutheast1
    )
    let response: MirrorResponse = try await client.invoke(
      "mirror",
      options: FunctionInvokeOptions(region: .any)
    )
    XCTAssertNil(response.headersDictionary["x-region"])
  }

  func testInvokeRegionSetOnlyOnTheConstructor() async throws {
    let client = FunctionsClient(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/functions/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_ANON_KEY)",
        "CustomHeader": "check me",
      ],
      region: .apSoutheast1
    )
    let response: MirrorResponse = try await client.invoke("mirror")
    XCTAssertEqual(response.headersDictionary["x-region"], "ap-southeast-1")
  }

  func testInvokeMirrorWithBodyFormData() async throws {
    throw XCTSkip("Unsupported body type.")
  }

  func testInvokeMirrowWithEncodableBody() async throws {
    let body = Body(one: "one", two: "two", three: "three", num: 11, flag: false)
    let response: MirrorResponse = try await client.functions.invoke(
      "mirror",
      options: FunctionInvokeOptions(
        headers: [
          "response-type": "json"
        ],
        body: body
      )
    )
    let responseBody = try response.body.decode(as: Body.self, decoder: JSONDecoder())
    XCTAssertEqual(responseBody, body)

    XCTAssertEqual(response.headersDictionary["content-type"], "application/json")
    XCTAssertEqual(response.headersDictionary["response-type"], "json")
  }

  func testInvokeMirrowWithDataBody() async throws {
    let body = Body(one: "one", two: "two", three: "three", num: 11, flag: false)

    let response: MirrorResponse = try await client.functions.invoke(
      "mirror",
      options: FunctionInvokeOptions(
        headers: [
          "response-type": "blob"
        ],
        body: try JSONEncoder().encode(body)
      )
    )

    guard let responseBodyData = response.body.stringValue?.data(using: .utf8),
      let responseBody = try? JSONDecoder().decode(Body.self, from: responseBodyData)
    else {
      XCTFail("Expected to receive body response as JSON string.")
      return
    }

    XCTAssertEqual(responseBody, body)

    XCTAssertEqual(response.headersDictionary["content-type"], "application/octet-stream")
    XCTAssertEqual(response.headersDictionary["response-type"], "blob")
  }
}

struct MirrorResponse: Decodable {
  let url: String
  let method: String
  let headers: AnyJSON
  let body: AnyJSON

  var headersDictionary: [String: String] {
    Dictionary(
      uniqueKeysWithValues: headers.arrayValue?.compactMap {
        $0.arrayValue?.compactMap(\.stringValue) ?? []
      }.map { ($0[0], $0[1]) } ?? []
    )
  }
}
struct Body: Codable, Equatable {
  let one, two, three: String
  let num: Int
  let flag: Bool
}
