//
//  StorageClient+Test.swift
//
//
//  Created by Guilherme Souza on 04/11/23.
//

import Foundation
import Helpers
import Storage

extension StorageClient {
  static func test(
    supabaseURL: String,
    apiKey: String,
    http: HTTPClientConfiguration = .init()
  ) -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: supabaseURL)!,
        headers: [
          .authorization: "Bearer \(apiKey)",
          .init("Apikey")!: apiKey,
          .xClientInfo: "storage-swift/x.y.z",
        ],
        http: http)
    )
  }
}
