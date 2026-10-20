//
//  DeferredRequestSnapshotTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import Foundation
import Mocker
import PostgREST
import TestHelpers
import Testing

#if os(Linux) || os(Android)
#else

  extension PostgrestMockerTests {
    @Suite(.mockerSerialized)
    struct DeferredRequestSnapshotTests {
      let fixture = PostgrestQueryFixture()

      @Test
      func mismatchedRequestSnapshotIsReported() async throws {
        Mock(
          url: fixture.url.appendingPathComponent("users"),
          ignoreQuery: true,
          statusCode: 200,
          data: [.get: Data("[]".utf8)]
        )
        .snapshotRequest(matches: { "a curl command this request cannot possibly produce" })
        .register()

        _ = try await fixture.sut.from("users").select().execute()

        withKnownIssue("the snapshot above is deliberately wrong, so comparing it must report") {
          assertDeferredRequestSnapshots()
        }
      }
    }
  }
#endif
