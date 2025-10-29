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
      file: StaticString = #filePath,
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

  func testBuildRequest() async throws {
    let runningTestCase = ActorIsolated(TestCase?.none)

    let encoder = PostgrestClient.Configuration.jsonEncoder
    encoder.outputFormatting = .sortedKeys

    let client = PostgrestClient(
      url: url,
      schema: nil,
      headers: ["X-Client-Info": "postgrest-swift/x.y.z"],
      logger: nil,
      fetch: { request in
        guard let runningTestCase = await runningTestCase.value else {
          XCTFail("execute called without a runningTestCase set.")
          return (Data(), URLResponse.empty())
        }

        await MainActor.run { [runningTestCase] in
          assertSnapshot(
            of: request,
            as: .curl,
            named: runningTestCase.name,
            record: runningTestCase.record,
            file: runningTestCase.file,
            testName: "testBuildRequest()",
            line: runningTestCase.line
          )
        }

        return (Data(), URLResponse.empty())
      },
      encoder: encoder
    )

    let testCases: [TestCase] = [
      TestCase(name: "select all users where email ends with '@supabase.co'") { client in
        client.from("users")
          .select()
          .like("email", pattern: "%@supabase.co")
      },
      TestCase(name: "insert new user") { client in
        try client.from("users")
          .insert(User(email: "johndoe@supabase.io"))
      },
      TestCase(name: "bulk insert users") { client in
        try client.from("users")
          .insert(
            [
              User(email: "johndoe@supabase.io"),
              User(email: "johndoe2@supabase.io", username: "johndoe2"),
            ]
          )
      },
      TestCase(name: "call rpc") { client in
        try client.rpc("test_fcn", params: ["KEY": "VALUE"])
      },
      TestCase(name: "call rpc without parameter") { client in
        try client.rpc("test_fcn")
      },
      TestCase(name: "call rpc with filter") { client in
        try client.rpc("test_fcn").eq("id", value: 1)
      },
      TestCase(name: "test all filters and count") { client in
        var query = client.from("todos").select()

        for op in PostgrestFilterBuilder.Operator.allCases {
          query = query.filter("column", operator: op.rawValue, value: "Some value")
        }

        return query
      },
      TestCase(name: "test in filter") { client in
        client.from("todos").select().in("id", values: [1, 2, 3])
      },
      TestCase(name: "test contains filter with dictionary") { client in
        client.from("users").select("name")
          .contains("address", value: ["postcode": 90210])
      },
      TestCase(name: "test contains filter with array") { client in
        client.from("users")
          .select()
          .contains("name", value: ["is:online", "faction:red"])
      },
      TestCase(name: "test or filter with referenced table") { client in
        client.from("users")
          .select("*, messages(*)")
          .or("public.eq.true,recipient_id.eq.1", referencedTable: "messages")
      },
      TestCase(name: "test upsert not ignoring duplicates") { client in
        try client.from("users")
          .upsert(User(email: "johndoe@supabase.io"))
      },
      TestCase(name: "bulk upsert") { client in
        try client.from("users")
          .upsert(
            [
              User(email: "johndoe@supabase.io"),
              User(email: "johndoe2@supabase.io", username: "johndoe2"),
            ]
          )
      },
      TestCase(name: "select after bulk upsert") { client in
        try client.from("users")
          .upsert(
            [
              User(email: "johndoe@supabase.io"),
              User(email: "johndoe2@supabase.io"),
            ],
            onConflict: "username"
          )
          .select()
      },
      TestCase(name: "test upsert ignoring duplicates") { client in
        try client.from("users")
          .upsert(User(email: "johndoe@supabase.io"), ignoreDuplicates: true)
      },
      TestCase(name: "query with + character") { client in
        client.from("users")
          .select()
          .eq("id", value: "Cigányka-ér (0+400 cskm) vízrajzi állomás")
      },
      TestCase(name: "query with timestampz") { client in
        client.from("tasks")
          .select()
          .gt("received_at", value: "2023-03-23T15:50:30.511743+00:00")
          .order("received_at")
      },
      TestCase(name: "query non-default schema") { client in
        client.schema("storage")
          .from("objects")
          .select()
      },
      TestCase(name: "select after an insert") { client in
        try client.from("users")
          .insert(User(email: "johndoe@supabase.io"))
          .select("id,email")
      },
      TestCase(name: "query if nil value") { client in
        client.from("users")
          .select()
          .is("email", value: nil)
      },
      TestCase(name: "likeAllOf") { client in
        client.from("users")
          .select()
          .likeAllOf("email", patterns: ["%@supabase.io", "%@supabase.com"])
      },
      TestCase(name: "likeAnyOf") { client in
        client.from("users")
          .select()
          .likeAnyOf("email", patterns: ["%@supabase.io", "%@supabase.com"])
      },
      TestCase(name: "iLikeAllOf") { client in
        client.from("users")
          .select()
          .iLikeAllOf("email", patterns: ["%@supabase.io", "%@supabase.com"])
      },
      TestCase(name: "iLikeAnyOf") { client in
        client.from("users")
          .select()
          .iLikeAnyOf("email", patterns: ["%@supabase.io", "%@supabase.com"])
      },
      TestCase(name: "containedBy using array") { client in
        client.from("users")
          .select()
          .containedBy("id", value: ["a", "b", "c"])
      },
      TestCase(name: "containedBy using range") { client in
        client.from("users")
          .select()
          .containedBy("age", value: "[10,20]")
      },
      TestCase(name: "containedBy using json") { client in
        client.from("users")
          .select()
          .containedBy("userMetadata", value: ["age": 18])
      },
      TestCase(name: "filter starting with non-alphanumeric") { client in
        client.from("users")
          .select()
          .eq("to", value: "+16505555555")
      },
      TestCase(name: "filter using Date") { client in
        client.from("users")
          .select()
          .gt("created_at", value: Date(timeIntervalSince1970: 0))
      },
      TestCase(name: "rpc call with head") { client in
        try client.rpc("sum", head: true)
      },
      TestCase(name: "rpc call with get") { client in
        try client.rpc("sum", get: true)
      },
      TestCase(name: "rpc call with get and params") { client in
        try client.rpc(
          "get_array_element",
          params: ["array": [37, 420, 64], "index": 2] as AnyJSON,
          get: true
        )
      },
    ]

    for testCase in testCases {
      await runningTestCase.withValue { $0 = testCase }
      let builder = try await testCase.build(client)
      _ = try? await builder.execute()
    }
  }

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
