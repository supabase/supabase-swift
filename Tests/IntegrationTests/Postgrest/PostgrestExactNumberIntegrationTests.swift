import Foundation
import PostgREST
import Testing

/// Numbers that neither `Int` nor `Double` holds exactly keep every digit through a live
/// PostgREST. `jsonb` stores a JSON number as a Postgres `numeric`, and `echo(json)` returns its
/// argument unchanged; both are in `supabase/migrations/`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestExactNumberIntegrationTests {
  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [.apikey: DotEnv.supabasePublishableKey]
    )
  )

  struct Amounts: Codable, Equatable {
    var price: Decimal
    var counter: UInt64
  }

  let amounts = Amounts(price: Decimal(string: "12345678901234567.89")!, counter: .max)

  @Test
  func aJSONBColumnKeepsTheExactDigits() async throws {
    struct UserData: Codable {
      var username: String
      var data: JSONValue
    }
    let username = "exact-\(UUID().uuidString)"

    let inserted: UserData = try await client.from("users")
      .insert(
        UserData(username: username, data: try JSONValue(amounts)), returning: .representation
      )
      .select("username,data")
      .single()
      .execute()
      .value
    try await client.from("users").delete().eq("username", value: username).execute()

    #expect(inserted.data.objectValue?["price"]?.numberValue?.description == "12345678901234567.89")
    #expect(
      inserted.data.objectValue?["counter"]?.numberValue?.description == "18446744073709551615")
    #expect(try inserted.data.decode(as: Amounts.self) == amounts)
  }

  @Test
  func anRPCArgumentAndResultKeepTheExactDigits() async throws {
    let params = try JSONValue(amounts)

    let echoed: JSONValue = try await client.rpc("echo", params: params).execute().value

    #expect(echoed == params)
    #expect(try echoed.decode(as: Amounts.self) == amounts)
  }
}
