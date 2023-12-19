import ConcurrencyExtras
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
      fetch: { request in
        guard let runningTestCase = await runningTestCase.value else {
          XCTFail("execute called without a runningTestCase set.")
          return (Data(), URLResponse())
        }

        await MainActor.run { [runningTestCase] in
          assertSnapshot(
            matching: request,
            as: .curl,
            named: runningTestCase.name,
            record: runningTestCase.record,
            testName: "testBuildRequest()"
          )
        }

        return (Data(), URLResponse())
      }
    )

    let testCases: [TestCase] = [
      TestCase(name: "select all users where email ends with '@supabase.co'") { client in
        await client.from("users")
          .select()
          .like("email", value: "%@supabase.co")
      },
      TestCase(name: "insert new user") { client in
        try await client.from("users")
          .insert(["email": "johndoe@supabase.io"])
      },
      TestCase(name: "call rpc") { client in
        try await client.rpc("test_fcn", params: ["KEY": "VALUE"])
      },
      TestCase(name: "call rpc without parameter") { client in
        try await client.rpc("test_fcn")
      },
      TestCase(name: "call rpc with filter") { client in
        try await client.rpc("test_fcn").eq("id", value: 1)
      },
      TestCase(name: "test all filters and count") { client in
        var query = await client.from("todos").select()

        for op in PostgrestFilterBuilder.Operator.allCases {
          query = query.filter("column", operator: op, value: "Some value")
        }

        return query
      },
      TestCase(name: "test in filter") { client in
        await client.from("todos").select().in("id", value: [1, 2, 3])
      },
      TestCase(name: "test contains filter with dictionary") { client in
        await client.from("users").select("name")
          .contains("address", value: ["postcode": 90210])
      },
      TestCase(name: "test contains filter with array") { client in
        await client.from("users")
          .select()
          .contains("name", value: ["is:online", "faction:red"])
      },
      TestCase(name: "test upsert not ignoring duplicates") { client in
        try await client.from("users")
          .upsert(["email": "johndoe@supabase.io"])
      },
      TestCase(name: "test upsert ignoring duplicates") { client in
        try await client.from("users")
          .upsert(["email": "johndoe@supabase.io"], ignoreDuplicates: true)
      },
      TestCase(name: "query with + character") { client in
        await client.from("users")
          .select()
          .eq("id", value: "Cigányka-ér (0+400 cskm) vízrajzi állomás")
      },
      TestCase(name: "query with timestampz") { client in
        await client.from("tasks")
          .select()
          .gt("received_at", value: "2023-03-23T15:50:30.511743+00:00")
          .order("received_at")
      },
      TestCase(name: "query non-default schema") { client in
        await client.schema("storage")
          .from("objects")
          .select()
      },
    ]

    for testCase in testCases {
      await runningTestCase.withValue { $0 = testCase }
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
