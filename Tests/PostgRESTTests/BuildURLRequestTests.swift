import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import PostgREST

@Suite
struct BuildURLRequestTests {
  let url = URL(string: "https://example.supabase.co")!

  struct RequestUser: Encodable {
    var email: String
    var username: String?
  }

  let transport = RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }

  @Test
  func queryWithNonASCIICharacters() async throws {
    try await send {
      $0.from("users")
        .select()
        .eq("id", value: "Cigányka-ér (0+400 cskm) vízrajzi állomás")
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?id=eq.Cig%C3%A1nyka-%C3%A9r%20(0+400%20cskm)%20v%C3%ADzrajzi%20%C3%A1llom%C3%A1s&select=*"
      """#
    }
  }

  @Test
  func queryWithTimestamptz() async throws {
    try await send {
      $0.from("tasks")
        .select()
        .gt("received_at", value: "2023-03-23T15:50:30.511743+00:00")
        .order("received_at")
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("tasks")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/tasks?order=received_at.asc&received_at=gt.2023-03-23T15:50:30.511743+00:00&select=*"
      """#
    }
  }

  @Test
  func filterStartingWithNonAlphanumeric() async throws {
    try await send {
      $0.from("users")
        .select()
        .eq("to", value: "+16505555555")
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?select=*&to=eq.+16505555555"
      """#
    }
  }

  @Test
  func filterUsingDate() async throws {
    try await send {
      $0.from("users")
        .select()
        .gt("created_at", value: Date(timeIntervalSince1970: 0))
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?created_at=gt.1970-01-01T00:00:00.000Z&select=*"
      """#
    }
  }

  @Test
  func allFilterOperators() async throws {
    try await send {
      var query = $0.from("todos").select()

      let allOperators: [PostgrestFilterBuilder.Operator] = [
        .eq, .neq, .gt, .gte, .lt, .lte, .like, .ilike, .match, .imatch, .is, .isdistinct, .in,
        .cs, .cd, .sl, .sr, .nxl, .nxr, .adj, .ov, .fts, .plfts, .phfts, .wfts,
      ]
      for op in allOperators {
        query = query.filter("column", operator: op.rawValue, value: "Some value")
      }

      return query
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("todos")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/todos?column=eq.Some%20value&column=neq.Some%20value&column=gt.Some%20value&column=gte.Some%20value&column=lt.Some%20value&column=lte.Some%20value&column=like.Some%20value&column=ilike.Some%20value&column=match.Some%20value&column=imatch.Some%20value&column=is.Some%20value&column=isdistinct.Some%20value&column=in.Some%20value&column=cs.Some%20value&column=cd.Some%20value&column=sl.Some%20value&column=sr.Some%20value&column=nxl.Some%20value&column=nxr.Some%20value&column=adj.Some%20value&column=ov.Some%20value&column=fts.Some%20value&column=plfts.Some%20value&column=phfts.Some%20value&column=wfts.Some%20value&select=*"
      """#
    }
  }

  @Test
  func containsWithArray() async throws {
    try await send {
      $0.from("users")
        .select()
        .contains("name", value: ["is:online", "faction:red"])
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?name=cs.%7Bis:online,faction:red%7D&select=*"
      """#
    }
  }

  @Test
  func containedByWithRange() async throws {
    try await send {
      $0.from("users")
        .select()
        .containedBy("age", value: "[10,20]")
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?age=cd.%5B10,20%5D&select=*"
      """#
    }
  }

  @Test
  func containedByWithJSON() async throws {
    try await send {
      $0.from("users")
        .select()
        .containedBy("userMetadata", value: ["age": 18])
    }

    try transport.assertFirstRequestSnapshot(.get, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/users?select=*&userMetadata=cd.%7B%22age%22:18%7D"
      """#
    }
  }

  @Test
  func upsertOneRow() async throws {
    try await send {
      try $0.from("users")
        .upsert(RequestUser(email: "johndoe@supabase.io"))
    }

    try transport.assertFirstRequestSnapshot(.post, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 31" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: resolution=merge-duplicates" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	--data "{\"email\":\"johndoe@supabase.io\"}" \
      	"https://example.supabase.co/users"
      """#
    }
  }

  @Test
  func selectAfterBulkUpsert() async throws {
    try await send {
      try $0.from("users")
        .upsert(
          [
            RequestUser(email: "johndoe@supabase.io"),
            RequestUser(email: "johndoe2@supabase.io"),
          ],
          onConflict: "username"
        )
        .select()
    }

    try transport.assertFirstRequestSnapshot(.post, url.appendingPathComponent("users")) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 66" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: resolution=merge-duplicates,return=representation" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	--data "[{\"email\":\"johndoe@supabase.io\"},{\"email\":\"johndoe2@supabase.io\"}]" \
      	"https://example.supabase.co/users?columns=%22email%22&on_conflict=username&select=*"
      """#
    }
  }

  @Test
  func rpcWithParams() async throws {
    try await send {
      try $0.rpc("test_fcn", params: ["KEY": "VALUE"])
    }

    try transport.assertFirstRequestSnapshot(.post, url.appendingPathComponent("rpc/test_fcn")) {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 15" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	--data "{\"KEY\":\"VALUE\"}" \
      	"https://example.supabase.co/rpc/test_fcn"
      """#
    }
  }

  @Test
  func rpcWithHead() async throws {
    try await send {
      try $0.rpc("sum", head: true)
    }

    try transport.assertFirstRequestSnapshot(.head, url.appendingPathComponent("rpc/sum")) {
      #"""
      curl \
      	--head \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/x.y.z" \
      	"https://example.supabase.co/rpc/sum"
      """#
    }
  }

  @Test
  func configurationKeepsTheHeadersItWasCreatedWith() throws {
    let client = try PostgrestClient(configuration: .init(url: url, schema: nil))
    #expect(client.configuration.headers.isEmpty)
  }

  @Test
  func configuredClientInfoIsMatchedCaseInsensitively() async throws {
    let capture = try QueryCapture(headers: [HTTPField.Name("x-client-info")!: "my-app/1.0"])
    _ = try? await capture.client.from("users").select().execute()
    #expect(capture.header("X-Client-Info") == "my-app/1.0")
  }

  @Test
  func requestsCarryTheDefaultClientInfo() async throws {
    let capture = try QueryCapture(headers: [:])
    _ = try? await capture.client.from("users").select().execute()
    #expect(
      capture.header("X-Client-Info")
        == "postgrest-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0"
    )
  }

  /// Sends the request `build` makes. The transport answers every request with an empty 200,
  /// so each test checks only the request.
  private func send(
    _ build: (PostgrestClient) throws -> any PostgrestExecutableBuilder
  ) async throws {
    let encoder = PostgrestClient.Configuration.jsonEncoder
    encoder.outputFormatting = .sortedKeys

    let client = try PostgrestClient(
      configuration: .init(
        url: url,
        schema: nil,
        headers: [.xClientInfo: "postgrest-swift/x.y.z"],
        http: .init(transport: transport),
        encoder: encoder,
        retryEnabled: false
      )
    )
    _ = try? await build(client).execute(options: FetchOptions())
  }
}
