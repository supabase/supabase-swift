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
          "Authorization": "Bearer \(apiKey)",
          "Apikey": apiKey,
          "X-Client-Info": "storage-swift/x.y.z",
        ],
        http: http)
    )
  }
}
