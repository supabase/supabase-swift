//
//  StorageApiTests.swift
//  Storage
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation
import Testing

@testable import Storage

@Suite
struct StorageApiTests {
  #if os(macOS) || os(Linux)
    /// `useNewHostname` rewrites the host at construction, so a URL with no host is a programmer
    /// error the initializer traps on, rather than a `URLError` surfacing on the first request.
    @Test
    func newHostnameWithoutAHostTraps() async {
      await #expect(processExitsWith: .failure) {
        _ = StorageApi(
          configuration: StorageClientConfiguration(
            url: URL(string: "project-ref")!,
            headers: [:],
            useNewHostname: true
          )
        )
      }
    }
  #endif
}
