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
  // `Mock.snapshotRequest` no-ops on Linux/Android (see `MockExtensions.swift`), so there is
  // nothing for this guard to observe on those platforms.
#else

  extension PostgrestMockerTests {
    /// Guards the fix for SDK-1520.
    ///
    /// `Mock.snapshotRequest` used to compare inside Mocker's request handler, which runs on the
    /// URL-loading queue where Swift Testing has no current test. The recorded issue was dropped,
    /// so every request snapshot in the package passed regardless of the request. If that
    /// regresses, this test fails because the expected mismatch never gets reported.
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
