import Foundation
import SnapshotTesting
import XCTest
@_spi(Internal) import _Helpers

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@MainActor
final class BuildURLRequestTests: XCTestCase {
  let url = URL(string: "https://example.supabase.co")!

  struct TestCase: Sendable {
    let name: String
    var record = false
    let build: @Sendable (PostgrestClient) async throws -> PostgrestBuilder
  }

  func testBuildRequest() async throws {
    let runningTestCase = ActorIsolated(TestCase?.none)

    let client = PostgrestClient(
      url: url,
      schema: nil,
      headers: ["X-Client-Info": "postgrest-swift/x.y.z"],
      fetch: { @MainActor request in
        runningTestCase.withValue { runningTestCase in
          guard let runningTestCase else {
            XCTFail("execute called without a runningTestCase set.")
            return (Data(), URLResponse())
          }

          assertSnapshot(
            matching: request,
            as: .curl,
            named: runningTestCase.name,
            record: runningTestCase.record,
            testName: "testBuildRequest()"
          )

          return (Data(), URLResponse())
        }
      }
    )

    let testCases: [TestCase] = [
      TestCase(name: "select all users where email ends with '@supabase.co'") { client in
        await client.from("users")
          .select()
          .like(column: "email", value: "%@supabase.co")
      },
      TestCase(name: "insert new user") { client in
        try await client.from("users")
          .insert(values: ["email": "johndoe@supabase.io"])
      },
      TestCase(name: "call rpc") { client in
        try await client.rpc(fn: "test_fcn", params: ["KEY": "VALUE"])
      },
      TestCase(name: "call rpc without parameter") { client in
        try await client.rpc(fn: "test_fcn")
      },
      TestCase(name: "test all filters and count") { client in
        var query = await client.from("todos").select()

        for op in PostgrestFilterBuilder.Operator.allCases {
          query = query.filter(column: "column", operator: op, value: "Some value")
        }

        return query
      },
      TestCase(name: "test in filter") { client in
        await client.from("todos").select().in(column: "id", value: [1, 2, 3])
      },
      TestCase(name: "test contains filter with dictionary") { client in
        await client.from("users").select(columns: "name")
          .contains(column: "address", value: ["postcode": 90210])
      },
      TestCase(name: "test contains filter with array") { client in
        await client.from("users")
          .select()
          .contains(column: "name", value: ["is:online", "faction:red"])
      },
      TestCase(name: "test upsert not ignoring duplicates") { client in
        try await client.from("users")
          .upsert(values: ["email": "johndoe@supabase.io"])
      },
      TestCase(name: "test upsert ignoring duplicates") { client in
        try await client.from("users")
          .upsert(values: ["email": "johndoe@supabase.io"], ignoreDuplicates: true)
      },
      TestCase(name: "query with + character") { client in
        await client.from("users")
          .select()
          .eq(column: "id", value: "Cigányka-ér (0+400 cskm) vízrajzi állomás")
      },
      TestCase(name: "query with timestampz") { client in
        await client.from("tasks")
          .select()
          .gt(column: "received_at", value: "2023-03-23T15:50:30.511743+00:00")
          .order(column: "received_at")
      },
    ]

    for testCase in testCases {
      runningTestCase.withValue { $0 = testCase }
      let builder = try await testCase.build(client)
      _ = try? await builder.execute()
    }
  }

  func testSessionConfiguration() async {
    let client = PostgrestClient(url: url, schema: nil)
    let clientInfoHeader = await client.configuration.headers["X-Client-Info"]
    XCTAssertNotNil(clientInfoHeader)
  }
}
