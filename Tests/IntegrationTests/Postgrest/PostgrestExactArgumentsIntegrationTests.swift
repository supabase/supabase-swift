import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

/// `get_status(name_param text)` finds a user by name. Users named with numbers that a `Double`
/// cannot hold are found by a `GET` call only when every digit of the argument reaches PostgREST.
@Function("get_status")
struct GetStatusByNumber {
  typealias Result = String?
  var nameParam: Decimal
}

struct NumberName: Encodable {
  var nameParam: UInt64

  enum CodingKeys: String, CodingKey {
    case nameParam = "name_param"
  }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestExactArgumentsIntegrationTests {
  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [.apikey: DotEnv.supabasePublishableKey]
    )
  )

  let bigInteger: UInt64 = 9_223_372_036_854_775_809
  let preciseDecimal = Decimal(string: "12345678901234567.89")!

  @Test
  func getArgumentsKeepEveryDigit() async throws {
    let names = ["\(bigInteger)", "\(preciseDecimal)"]
    // An email makes the PostgrestTransformsTests setup remove a row a failed run leaves behind.
    try await client.from("users")
      .upsert(
        names.map { ["username": $0, "email": "\($0)@example.com", "status": "OFFLINE"] },
        onConflict: "username"
      )
      .execute()

    let untyped: String? =
      try await client
      .rpc("get_status", params: NumberName(nameParam: bigInteger), get: true)
      .execute().value
    let typed = try await client.rpc(GetStatusByNumber(nameParam: preciseDecimal))
      .readOnly().execute().value

    try await client.from("users").delete().in("username", values: names).execute()
    #expect(untyped == "OFFLINE")
    #expect(typed == "OFFLINE")
  }
}
