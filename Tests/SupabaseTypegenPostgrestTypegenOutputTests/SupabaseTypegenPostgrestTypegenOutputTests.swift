//
//  SupabaseTypegenPostgrestTypegenOutputTests.swift
//  SupabaseTypegenPostgrestTypegenOutputTests
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes
import PostgrestMacros
import TestHelpers
import Testing

// `Generated.swift` is `supabase-typegen --access-control public` run on postgrest-typegen's own
// fixture. It is here, not with the integration schema, because the integration schema has no
// relation outside `public`.

@Suite
struct SupabaseTypegenPostgrestTypegenOutputTests {
  @Test
  func prefixedRelationSendsItsSchemaInAcceptProfile() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), Data("[]".utf8))
    }
    let client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      http: .init(transport: transport)
    )
    _ = try await client.from(InventoryItems.self).select()
      .where { $0.status.eq(.stocked) }
      .execute()

    let request = try #require(transport.requests.first?.head)
    #expect(request.headerFields[HTTPField.Name("Accept-Profile")!] == "inventory")
    #expect(request.path?.removingPercentEncoding == "/items?select=*&status=eq.STOCKED")
  }
}
